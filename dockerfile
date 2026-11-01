FROM alpine:latest

COPY . /zerotty

RUN apk add --no-cache \
        sudo \
        curl \
        bash \
        xz \
        git \
        ca-certificates \
        bison \
        minisign \
        glslang \
        zstd \
        zip \ 
        python3

RUN /zerotty/ci/install-zig.sh

# this is just to trigger compiling maker
RUN zig fetch --help

WORKDIR /zerotty
