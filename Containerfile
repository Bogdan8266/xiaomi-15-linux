FROM alpine:edge
RUN apk update && apk add --no-cache \
    clang llvm lld gcc musl-dev \
    make bc bison flex openssl openssl-dev elfutils-dev \
    linux-headers perl bash diffutils findutils git python3 ncurses-dev tar xz
