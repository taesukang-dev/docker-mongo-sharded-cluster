#!/bin/bash

function rs0() {
    docker exec -it mongo-rs0-primary \
    mongosh -u root -p 1234 --host 127.0.0.1 --port 27018 \
    --eval 'rs.initiate({_id: "rs0", members: [{_id: 0, host: "192.168.10.10:27018"}, {_id: 1, host: "192.168.10.11:17018"}, {_id: 2, host: "192.168.10.12:27021", arbiterOnly: true}]})'
}

function rs1() {
    docker exec -it mongo-rs1-primary \
    mongosh -u root -p 1234 --host 127.0.0.1 --port 27018 \
    --eval 'rs.initiate({_id: "rs1", members: [{_id: 0, host: "192.168.10.11:27018"}, {_id: 1, host: "192.168.10.10:17018"}, {_id: 2, host: "192.168.10.12:27022", arbiterOnly: true}]})'
}

function config() {
    docker exec -it mongo-config \
    mongosh -u root -p 1234 --host 127.0.0.1 --port 27019 \
    --eval 'rs.initiate({_id: "cfgrepl", members: [{_id: 0, host: "192.168.10.10:27019"}, {_id: 1, host: "192.168.10.11:27019"}, {_id: 2, host: "192.168.10.12:27019"}]})'
}

function mongos() {
  docker exec -it mongos mongosh -u root -p 1234 --port 27017 --eval 'sh.addShard("rs0/192.168.10.10:27018,192.168.10.11:17018")'
  docker exec -it mongos mongosh -u root -p 1234 --port 27017 --eval 'sh.addShard("rs1/192.168.10.10:17018,192.168.10.11:27018")'
  # 테이블 생성, sharding 이 가능한 Table 로 생성 필요
  # 테이블 생성 후 테이블을 사용할 수 있는 계정 생성
}

case $x in
  rs0)
    rs0
  ;;
  rs1)
    rs1
  ;;
  config)
    config
  ;;
  mongos)
    mongos
  ;;
esac

