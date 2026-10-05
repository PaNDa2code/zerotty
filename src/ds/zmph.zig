const std = @import("std");
const Allocator = std.mem.Allocator;
const ArrayList = std.ArrayList;
const toBytes = std.mem.toBytes;

fn staticList(comptime T: type, comptime n: usize, comptime fill: T) type {
    return struct {
        items: [n]T = [_]T{fill} ** n,
        len: usize = 0,
        fn decOrder(_: void, lhs: @This(), rhs: @This()) bool {
            return lhs.len > rhs.len;
        }
        fn append(self: *@This(), value: T) void {
            if (self.len >= self.items.len)
                @compileError("using .append() method on fully staticList");
            self.items[self.len] = value;
            self.len += 1;
        }
        fn pop(self: *@This()) T {
            if (self.len == 0)
                @compileError("using .pop() method on empty staticList");
            self.len -= 1;
            return self.items[self.len];
        }
        fn clear(self: *@This()) void {
            self.len = 0;
        }
        fn has(self: *@This(), value: T) bool {
            for (self.items) |item| {
                if (value == item) return true;
            }
            return false;
        }
    };
}

pub fn PerfectHashMap(comptime K: type, comptime V: type) type {
    return struct {
        const Self = @This();
        const v_fill: V = undefined;
        const max_usize: comptime_int = std.math.maxInt(usize);
        const max_isize: comptime_int = std.math.maxInt(isize);

        const empty_disps = [0]isize{};
        const empty_keys = [0]K{};
        const empty_values = [0]V{};

        const empty_kvs = KVs{
            .keys = &empty_keys,
            .values = &empty_values,
            .len = 0,
        };

        const KVs = struct {
            keys: [*]const K,
            values: [*]const V,
            len: usize,
        };

        kvs: *const KVs = &empty_kvs,
        len: usize = 0,
        displacement_table: [*]const isize = &empty_disps,
        allocator: Allocator = undefined,

        inline fn hash(key: K, seed: u32, mod_value: usize) usize {
            return if (K == []const u8)
                std.hash.Murmur3_32.hashWithSeed(key, seed) % mod_value
            else
                std.hash.Murmur3_32.hashWithSeed(std.mem.asBytes(&key), seed) % mod_value;
        }

        fn sortBucketsDec(_: void, lhs: ArrayList(usize), rhs: ArrayList(usize)) bool {
            return lhs.items.len > rhs.items.len;
        }

        /// `O(N²)` runtime initial
        pub fn init(allocator: Allocator, kv_list: anytype) !Self {
            const n = kv_list.len;

            var keys = try allocator.alloc(K, n);
            var values = try allocator.alloc(V, n);
            var displacement_table = try allocator.alloc(isize, n);

            var value_setted = try allocator.alloc(bool, n);
            defer allocator.free(value_setted);
            @memset(value_setted, false);

            // @memset(values, null);
            @memset(displacement_table, std.math.maxInt(isize));

            var buckets = try allocator.alloc(ArrayList(usize), n);

            @memset(buckets, try @TypeOf(buckets[0]).initCapacity(allocator, 0));

            defer {
                for (buckets) |*bucket| {
                    bucket.deinit(allocator);
                }
                allocator.free(buckets);
            }

            for (kv_list, 0..) |kv, key_index| {
                try buckets[hash(kv.@"0", 0, n)].append(allocator, key_index);
            }

            std.mem.sort(ArrayList(usize), buckets, {}, sortBucketsDec);

            var slots = try ArrayList(usize).initCapacity(allocator, n);
            defer slots.deinit(allocator);

            var bucket_index: usize = 0;

            // Handle buckets with more than one key
            for (buckets) |bucket| {
                if (bucket.items.len <= 1) break;

                slots.clearRetainingCapacity();
                var displacement: u32 = 1;
                var item: usize = 0;

                while (item < bucket.items.len) {
                    const kv_index = bucket.items[item];
                    const kv = kv_list[kv_index];
                    const slot = hash(kv.@"0", displacement, n);

                    if (value_setted[slot] or std.mem.containsAtLeast(usize, slots.items, 1, &.{slot})) {
                        slots.clearRetainingCapacity();
                        displacement += 1;
                        item = 0;
                    } else {
                        slots.append(allocator, slot) catch unreachable;
                        item += 1;
                    }
                }

                // no need to set all the table, since the bucket has a keys with the same hash1 result
                displacement_table[hash(kv_list[bucket.items[0]].@"0", 0, n)] = @intCast(displacement);

                for (0..bucket.items.len) |i| {
                    keys[slots.items[i]] = kv_list[bucket.items[i]].@"0";
                    value_setted[slots.items[i]] = true;
                    if (V != void) {
                        values[slots.items[i]] = kv_list[bucket.items[i]].@"1";
                    }
                }
                bucket_index += 1;
            }

            var free_slots = try ArrayList(usize).initCapacity(allocator, 0);
            defer free_slots.deinit(allocator);

            for (value_setted, 0..) |value_is_set, i| {
                if (!value_is_set)
                    try free_slots.append(allocator, i);
            }

            // Handle buckets with one key
            for (buckets[bucket_index..]) |bucket| {
                if (bucket.items.len == 0) break;
                const slot = free_slots.pop().?;
                displacement_table[hash(kv_list[bucket.items[0]].@"0", 0, n)] = -@as(isize, @intCast(slot)) - 1;
                keys[slot] = kv_list[bucket.items[0]].@"0";
                values[slot] = kv_list[bucket.items[0]].@"1";
                value_setted[slot] = true;
            }

            const final_keys = keys.ptr;
            const final_values = values.ptr;
            var kvs = try allocator.create(KVs);
            kvs.keys = final_keys;
            kvs.values = final_values;
            kvs.len = n;
            const final_kvs = kvs;
            return .{
                .kvs = final_kvs,
                .allocator = allocator,
                .displacement_table = @ptrCast(displacement_table.ptr),
                .len = n,
            };
        }

        /// Same as `init` but runs only in compile time returning a constent hash map
        pub inline fn comptimeInit(comptime kv_list: anytype) Self {
            comptime {
                const n = kv_list.len;

                // O(N²)
                @setEvalBranchQuota(@max(n * n, 100_000));

                var keys: [n]K = [1]K{undefined} ** n;
                var values: [n]V = [1]V{undefined} ** n;
                var value_setted: [n]bool = [1]bool{false} ** n;
                var displacement_table: [n]isize = [1]isize{0} ** n;

                const bucketType = staticList(usize, n, 0);

                var buckets: [n]bucketType = [1]bucketType{.{}} ** n;

                for (kv_list, 0..) |kv, key_index| {
                    buckets[hash(kv.@"0", 0, n)].append(key_index);
                }

                std.mem.sort(bucketType, &buckets, {}, bucketType.decOrder);

                var slots = staticList(usize, n, 0){};

                var bucket_index: usize = 0;

                for (buckets) |bucket| {
                    if (bucket.len <= 1) break;
                    slots.clear();
                    var displacement: u32 = 1;
                    var item: usize = 0;
                    while (item < bucket.len) {
                        const slot = hash(kv_list[bucket.items[item]].@"0", displacement, n);
                        if (value_setted[slot] or std.mem.containsAtLeast(usize, slots.items[0..slots.len], 1, &.{slot})) {
                            slots.clear();
                            displacement += 1;
                            item = 0;
                        } else {
                            slots.append(slot);
                            item += 1;
                        }
                    }

                    displacement_table[hash(kv_list[bucket.items[0]].@"0", 0, n)] = @intCast(displacement);

                    for (0..bucket.len) |i| {
                        keys[slots.items[i]] = kv_list[bucket.items[i]].@"0";
                        value_setted[slots.items[i]] = true;
                        if (V != void) {
                            values[slots.items[i]] = kv_list[bucket.items[i]].@"1";
                        }
                    }
                    bucket_index += 1;
                }

                var free_slots = staticList(usize, n, max_usize){};

                for (value_setted, 0..) |value_is_set, i| {
                    if (!value_is_set)
                        free_slots.append(i);
                }

                for (buckets[bucket_index..]) |bucket| {
                    if (bucket.len == 0) break;
                    const slot = free_slots.pop();
                    displacement_table[hash(kv_list[bucket.items[0]].@"0", 0, n)] = -@as(isize, @intCast(slot)) - 1;
                    keys[slot] = kv_list[bucket.items[0]].@"0";
                    if (V != void)
                        values[slot] = kv_list[bucket.items[0]].@"1";
                }

                const final_keys = keys;
                const final_values = values;
                const final_displacement_table = displacement_table;
                const kvs = KVs{
                    .keys = &final_keys,
                    .values = &final_values,
                    .len = n,
                };

                return .{
                    .kvs = &kvs,
                    .displacement_table = @ptrCast(&final_displacement_table),
                    .len = n,
                };
            }
        }

        pub fn deinit(self: *const Self) void {
            self.allocator.free(self.kvs.keys[0..self.len]);
            self.allocator.free(self.kvs.values[0..self.len]);
            self.allocator.destroy(self.kvs);
            self.allocator.free(self.displacement_table[0..self.len]);
        }

        pub fn getIndex(self: *const Self, key: K) ?usize {
            const displacement = self.displacement_table[hash(key, 0, self.len)];
            const index = if (displacement < 0)
                (@as(usize, @intCast(-displacement)) - 1)
            else
                hash(key, @intCast(displacement), self.len);

            if ((K == []const u8 and std.mem.eql(u8, key, self.kvs.keys[index])) or
                std.mem.eql(u8, &toBytes(key), &toBytes(self.kvs.keys[index])))
                return index;

            return null;
        }

        pub fn has(self: *const Self, key: K) bool {
            return self.getIndex(key) != null;
        }

        pub fn get(self: *const Self, key: K) ?V {
            return self.kvs.values[self.getIndex(key) orelse return null];
        }
    };
}

test "MinimalPerfectHashMap" {
    const map = try PerfectHashMap([]const u8, []const u8).init(std.testing.allocator, &words);
    defer map.deinit();

    for (words) |word| {
        try std.testing.expectEqualStrings(word[0], map.get(word[0]).?);
    }
}

test "MinimalPerfectComptimeHashMap" {
    const map = PerfectHashMap([]const u8, []const u8).comptimeInit(words);
    for (words) |word| {
        try std.testing.expectEqualStrings(word[0], map.get(word[0]).?);
    }
}

const words = [116]struct { []const u8, []const u8 }{
    .{ "apple", "apple" },
    .{ "banana", "banana" },
    .{ "cherry", "cherry" },
    .{ "date", "date" },
    .{ "elderberry", "elderberry" },
    .{ "fig", "fig" },
    .{ "grape", "grape" },
    .{ "honeydew", "honeydew" },
    .{ "kiwi", "kiwi" },
    .{ "lemon", "lemon" },
    .{ "mango", "mango" },
    .{ "nectarine", "nectarine" },
    .{ "orange", "orange" },
    .{ "papaya", "papaya" },
    .{ "quince", "quince" },
    .{ "raspberry", "raspberry" },
    .{ "strawberry", "strawberry" },
    .{ "tangerine", "tangerine" },
    .{ "ugli", "ugli" },
    .{ "vanilla", "vanilla" },
    .{ "watermelon", "watermelon" },
    .{ "xigua", "xigua" },
    .{ "yellowfruit", "yellowfruit" },
    .{ "zucchini", "zucchini" },
    .{ "avocado", "avocado" },
    .{ "blueberry", "blueberry" },
    .{ "cantaloupe", "cantaloupe" },
    .{ "dragonfruit", "dragonfruit" },
    .{ "eggplant", "eggplant" },
    .{ "feijoa", "feijoa" },
    .{ "guava", "guava" },
    .{ "huckleberry", "huckleberry" },
    .{ "jackfruit", "jackfruit" },
    .{ "kumquat", "kumquat" },
    .{ "lychee", "lychee" },
    .{ "mulberry", "mulberry" },
    .{ "noni", "noni" },
    .{ "olive", "olive" },
    .{ "pineapple", "pineapple" },
    .{ "quenepa", "quenepa" },
    .{ "rambutan", "rambutan" },
    .{ "starfruit", "starfruit" },
    .{ "tomato", "tomato" },
    .{ "ume", "ume" },
    .{ "violetfruit", "violetfruit" },
    .{ "wolfberry", "wolfberry" },
    .{ "ximenia", "ximenia" },
    .{ "yangmei", "yangmei" },
    .{ "zinfandel", "zinfandel" },
    .{ "carrot", "carrot" },
    .{ "broccoli", "broccoli" },
    .{ "cauliflower", "cauliflower" },
    .{ "spinach", "spinach" },
    .{ "kale", "kale" },
    .{ "lettuce", "lettuce" },
    .{ "pumpkin", "pumpkin" },
    .{ "squash", "squash" },
    .{ "yam", "yam" },
    .{ "beet", "beet" },
    .{ "radish", "radish" },
    .{ "turnip", "turnip" },
    .{ "parsnip", "parsnip" },
    .{ "celery", "celery" },
    .{ "cucumber", "cucumber" },
    .{ "pepper", "pepper" },
    .{ "onion", "onion" },
    .{ "garlic", "garlic" },
    .{ "shallot", "shallot" },
    .{ "chive", "chive" },
    .{ "leek", "leek" },
    .{ "pea", "pea" },
    .{ "bean", "bean" },
    .{ "lentil", "lentil" },
    .{ "chickpea", "chickpea" },
    .{ "soybean", "soybean" },
    .{ "edamame", "edamame" },
    .{ "peanut", "peanut" },
    .{ "almond", "almond" },
    .{ "cashew", "cashew" },
    .{ "walnut", "walnut" },
    .{ "pistachio", "pistachio" },
    .{ "pecan", "pecan" },
    .{ "hazelnut", "hazelnut" },
    .{ "macadamia", "macadamia" },
    .{ "brazilnut", "brazilnut" },
    .{ "www.google.com", "www.google.com" },
    .{ "www.facebook.com", "www.facebook.com" },
    .{ "www.twitter.com", "www.twitter.com" },
    .{ "www.linkedin.com", "www.linkedin.com" },
    .{ "www.github.com", "www.github.com" },
    .{ "www.stackoverflow.com", "www.stackoverflow.com" },
    .{ "www.reddit.com", "www.reddit.com" },
    .{ "www.quora.com", "www.quora.com" },
    .{ "https://openai.com", "https://openai.com" },
    .{ "https://developer.mozilla.org", "https://developer.mozilla.org" },
    .{ "https://ziglang.org", "https://ziglang.org" },
    .{ "https://example.com", "https://example.com" },
    .{ "https://mywebsite.com", "https://mywebsite.com" },
    .{ "file://local/path/to/resource", "file://local/path/to/resource" },
    .{ "ftp://myserver.com/resource", "ftp://myserver.com/resource" },
    .{ "http://mywebsite.com/page", "http://mywebsite.com/page" },
    .{ "admin", "admin" },
    .{ "user", "user" },
    .{ "guest", "guest" },
    .{ "superuser", "superuser" },
    .{ "root", "root" },
    .{ "test", "test" },
    .{ "alpha", "alpha" },
    .{ "beta", "beta" },
    .{ "gamma", "gamma" },
    .{ "delta", "delta" },
    .{ "epsilon", "epsilon" },
    .{ "theta", "theta" },
    .{ "sigma", "sigma" },
    .{ "omega", "omega" },
    .{ "pi", "pi" },
};
