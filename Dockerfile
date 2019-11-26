FROM crystallang/crystal:latest

RUN apt-get update && apt-get install -y sqlite3 libsqlite3-dev
RUN mkdir -p /opt/file-index-cr/bin
WORKDIR /opt/file-index-cr
ADD src /opt/file-index-cr/src
ADD spec /opt/file-index-cr/spec
ADD lib /opt/file-index-cr/lib
ADD docs /opt/file-index-cr/docs
ADD shard.yml /opt/file-index-cr/shard.yml

RUN shards build file-index

CMD ["bash"]
