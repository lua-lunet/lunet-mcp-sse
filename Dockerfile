FROM debian:trixie-slim

RUN apt-get update && apt-get install -y --no-install-recommends \
    curl \
    ca-certificates \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /app

COPY bin/lunet usr/local/bin/lunet
COPY lib/*.so usr/local/lib/
COPY app/ /app/app/
COPY run.sh /app/

ENV LUA_CPATH=/usr/local/lib/?.so;;

RUN chmod +x /app/run.sh

EXPOSE 8080

CMD ["/app/run.sh"]