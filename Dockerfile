# crystal build
FROM crystallang/crystal:0.34.0-alpine-build as crystal

WORKDIR /build

COPY ./shard.yml /build/
COPY ./shard.lock /build/
RUN mkdir src
COPY ./src /build/src

RUN shards
RUN shards build site --release --static

# prod
FROM alpine:3

RUN apk add espeak

WORKDIR /app
COPY --from=crystal /build/bin/site /app/site
RUN mkdir /app/out

EXPOSE 3750
CMD ["/app/site"]
