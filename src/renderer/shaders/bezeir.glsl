vec2 leaner_interpolation(vec2 p0, vec2 p1, float t)
{
    return (1.0 - t) * p0 + t * p1;
}

vec2 quadratic_interpolation(vec2 p0, vec2 p1, vec2 p2, float t)
{
    float u = 1.0 - t;
    return u * u * p0 + 2.0 * u * t * p1 + t * t * p2;
}

vec2 cubic_interpolation(vec2 p0, vec2 p1, vec2 p2, vec2 p3, float t)
{
    float u = 1.0 - t;
    float tt = t * t;
    float uu = u * u;
    float uuu = uu * u;
    float ttt = tt * t;

    return uuu * p0 +
        3.0 * uu * t * p1 +
        3.0 * u * tt * p2 +
        ttt * p3;
}
