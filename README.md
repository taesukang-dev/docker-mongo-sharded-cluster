# Mongo Sharded Cluster

> 이 프로젝트는 Sharded Mongo Cluster 를 Docker 로 올려보며 간단하게 알아봅니다. <br />
> production level에서는 전혀 권장되지 않는 설정입니다.<br />
> <a href="https://liltdevs.tistory.com/216">참고 글. MongoDB 총정리</a>
> <a href="https://liltdevs.tistory.com/217">정체된 MongoDB Sharded Cluster 블로그 글</a>

<img src="mongo.drawio.png" />

- Scale-out 을 위한 MongoDB Sharded Cluster
  - Collection 을 수평 확장(Sharding)하며 각 Shard 는 Read Write Split 을 동시에 적용하여 빠른 성능을 지원
- MongoDB Sharded Cluster 구성
  - HA 를 위한 Replication Set 2집합, 총 6대(가로 Shard A, B)
  - Sharding Configuration 을 관리하는 Config 서버 3대
  - Router 역할을 하는 Mongos, HA 를 위해 2대
  - 최소 요구 사항 총 11대
- 데이터는 Shard key 를 기준으로 Shard A/B 에 나눠서 적재 됨
  - 차후 Select 할 때에는 쿼리를 병렬 수행, A/B 에서 각각 수행
- Replication Set 에는 Primary, Secondary, Arbiter 가 존재
  - Primary : Write 수행 Master
  - Secondary : Read 수행 Slave
  - Arbiter : 정족수를 위한 Node, 실제 데이터는 갖고 있지 않음
    - Arbiter 는 Secondary 로 변경하는 것이 좋음
    - Write Concern 을 majority 로 설정할 때 3대 중 2대만 가용하다면, 1대는 Arbiter 라면 제대로 된 판단하기 어려움
    - 자세한 내용은 <a href="https://liltdevs.tistory.com/216">MongoDB 총정리 블로그 글</a>을 참조
- Client 는 Mongos, Router 로 접근한다.
  - 1/2 에 27017로 올라가있는 Mongos 에 CRUD query 를 수행하면 Mongos 가 각 Shard에 query 를 분배한다.
- Mongos 는 Config Server 를 참조한다.
  - mongos 내 config database 에서 확인 가능
  - Cluster 의 Metadata(chunks, databases, collections, shards...) 를 관리한다.
- primary, secondary, arbiter 는 물리적 위치를 다르게 해 고가용성, 내결함성을 만족해야 한다.
- Mongos 도 최소 2대로 고가용성, 내결함성을 만족해야 한다.
  
## 설치
- 1, 2, 3 은 각각 물리 machine 이다.
  - 아래에서 실행하는 mongosh 명령어의 host 에는 port 는 동일하지만 각 instance 의 ip 를 사용해야 한다.
- 각각의 directory 를 원하는 machine 에 위치 시킨다.
- 1, 2, 3 Base Directory(e.g. `.../188/.`, docker-compose 와 같은 위치)에서 replication 에서 인증을 위한 Key 를 생성한다.
  - `openssl rand -base64 756 > mongodb.key`
  - `chmod 400 mongodb.key`, `chown 999:999 mongodb.key` 로 권한을 조정하여 mongodb 가 사용할 수 있게 한다.
- docker-compose 를 각각 machine 에서 실행한다.
- 이후 replication 을 primary node 에서 실행한다. (각 Node port 는 위 구성도를 참고)
```bash
# 188에서 수행, Replication Set 0번 설정
$ docker exec -it mongo-rs0-primary mongosh -u root -p 1234 --port 27018
mongo > rs.initiate({
	 _id: "rs0",
	 members: [
	   {_id: 0, host: "192.168.10.10:27018", priority: 2}, # priority 는 master 가 될 가중치, 높을 수록 우선순위 높음
	   {_id: 1, host: "192.168.10.11:17018", priority: 1},
	   # 위에서 상술했듯 Arbiter 는 데이터를 갖고 있지 않음, 다만 Secondary Node 로 띄우는 것을 권장
	   # 만약 Secondary 로 띄울 때에는
	   # {_id: 2, host: "192.168.10.12:27021"} 로 설정 가능 
	   {_id: 2, host: "192.168.10.12:27021", arbiterOnly:true, priority: 0} 
	 ]
});
# Replication 확인
mongo > rs.status()

# 189에서 수행, Replication Set 1번 설정
$ docker exec -it mongo-rs1-primary mongosh -u root -p 1234 --port 27018
mongo > rs.initiate({
	 _id: "rs1",
	 members: [
	   {_id: 0, host: "192.168.10.11:27018", priority: 2}, # priority 는 master 가 될 가중치, 높을 수록 우선순위 높음
	   {_id: 1, host: "192.168.10.10:17018", priority: 1},
	   # 위에서 상술했듯 Arbiter 는 데이터를 갖고 있지 않음, 다만 Secondary Node 로 띄우는 것을 권장
	   # 만약 Secondary 로 띄울 때에는
	   # {_id: 2, host: "192.168.10.12:27022"} 로 설정 가능 
	   {_id: 2, host: "192.168.10.12:27022", arbiterOnly:true, , priority: 0}
	 ]
});
# Replication 확인
mongo > rs.status()

# 188에서 수행, Config Server Replication Set 설정
$ docker exec -it mongo-config mongosh -u root -p 1234 --port 27019
mongo > rs.initiate( {
   _id : "cfgrepl",
   members: [
      { _id: 0, host: "192.168.10.10:27019"},
      { _id: 1, host: "192.168.10.11:27019"},
      { _id: 2, host: "192.168.10.12:27019"}
   ]
})
# Replication 확인
mongo > rs.status()
```
- 이후 router 로 사용할 mongos 를 설정한다.
  - 참고 `./mongos/mongos.conf` 내에는 configuration replication 에 대해 설정되어있다.
  ```yaml
    sharding:
        configDB: "cfgrepl/..."
  ```
```bash
$ docker exec -it mongos mongosh -u root -p 1234 --port 27017
# Replication Set 2개에 대해 설정, Arbiter 는 제외한다. 
mongo > sh.addShard("rs0/192.168.10.10:27018,192.168.10.11:17018")
mongo > sh.addShard("rs1/192.168.10.10:17018,192.168.10.11:27018")
# 클러스터 상태 확인
mongo > sh.status()
# sharding 이 가능한 Database 생성
mongo > sh.enableSharding("test_database")
# collection(RDB 의 Table) 을 생성하고 sharding key 를 결정
mongo > sh.shardCollection("test_database.test", {sharding_key: "hashed"})
# sharding cluster 확인
mongo > sh.status()
# 위 데이터베이스에 접속하기 위한 user 생성
mongo > use test_database
mongo > db.createUser({
    user: "${USER}",
    pwd: "${PASSWORD}}",
    roles: [{role: "readWrite", db: "test_database"}]
})
# 유저가 생성되었는지 확인
mongo > db.getUsers()
```

## Spring 연동
- <a href="https://www.mongodb.com/docs/v6.2/reference/connection-string/">MongoDB Connection URI Example</a>
  ```yaml
    spring:
      data:
        mongodb:
          # Auth_SOURCE 는 대체로 admin, user 를 전역으로 권한 주고 사용할 예정이기 때문에
          # Database 는 shard 설정이 되어있는 Database 여야 함
          uri: mongodb://${USER}:${PASSWORD}@192.168.1.222:27017,192.168.1.222:27717/${DATABASE}?authSource=${AUTH_SOURCE}
  ```
  - 위 공식문서에서 알려주는 형태로 application.yaml 에 `spring.data.mongodb.uri` 항목에 기입

  ```java
  @EnableReactiveMongoAuditing
  @RequiredArgsConstructor
  @Configuration
  public class MongoConfig extends AbstractReactiveMongoConfiguration {
  private static final String DB_NAME = "testdb";
  
      private final SystemKeyOneService systemKeyOneService;
  
      @NotNull
      @Override
      @Bean
      public MongoClient reactiveMongoClient() {
          final String mongoUri = systemKeyOneService.getConfig().getMongoUri();
          ConnectionString connection = new ConnectionString(mongoUri);
          // connection pool 설정
          MongoClientSettings settings = MongoClientSettings.builder()
                  .retryWrites(true)
                  .applyConnectionString(connection)
                  .applyToConnectionPoolSettings((ConnectionPoolSettings.Builder builder) -> {
                      builder.maxSize(10)
                              .minSize(10)
                              .maxConnectionLifeTime(100, TimeUnit.SECONDS)
                              .maxConnectionIdleTime(100, TimeUnit.SECONDS)
                              .maxWaitTime(5, TimeUnit.SECONDS);
                  })
                  .applyToSocketSettings(builder -> {
                      builder.connectTimeout(100, TimeUnit.SECONDS);
                  })
                  .applicationName("TEST")
                  .build();
          return MongoClients.create(settings);
      }
  
      @Bean
      public ReactiveMongoTemplate reactiveMongoTemplate(MongoClient reactiveMongoClient) {
          return new ReactiveMongoTemplate(reactiveMongoClient, getDatabaseName());
      }
  
      @Bean(name = "mongoTx")
      // MongoDB 는 기본값으로 Transaction 을 지원하지 않는다 -> BASE 이기 때문에.
      // Transaction을 사용하려면 아래와 같이 TransactionManager 를 정의한다.
      // TransactionManager 가 MongoDB 하나라면 @Transactional 로 사용할 수 있지만 (TransactionManager 가 1개이기 때문에)
      // 만약 다른 DB 와 함께 사용 중이라면 서비스 로직에 @Transactional("mongoTx") 를 기입해야 Transaction 이 정상 작동한다.
      public ReactiveMongoTransactionManager reactiveMongoTransactionManager(ReactiveMongoDatabaseFactory dbFactory) {
          return new ReactiveMongoTransactionManager(dbFactory);
      }
  
      @NotNull
      @Override
      public String getDatabaseName() { // 접속할 Database 명시
          return DB_NAME;
      }
  
      @Override
      public boolean autoIndexCreation() { // 자동으로 index 설정 여부
          return true;
      }
  }
  ```
- 프로그래밍 방식으로 Connection Pool 관련 설정 예시

```java
  @Transactional("mongoTx")
  public Mono<Test> test() {
      Test test1 = new Test("test1");
      Test test2 = new Test("test2");
      return repository.save(test1)
              .flatMap(data -> Mono.error(new RuntimeException("test")))
              .flatMap(data -> repository.save(test2));
  }
```
- Mongodb Transaction 을 사용하는 예시
  - 참고. 만약 transactional 을 다른 제품간 결합하고 싶을 때 
    - ChainedTransactionManager 를 사용할 수 있지만 현재는 deprecated 된 상태이고
    - JTA(XA) 를 사용하여 2PC 로 관리하는 방식으로 해야된다. -> management point가 너무 비대해진다...

  ```java
  // entity
  @Document(collection = "employees") // Collection(rdb 의 table) 설정
  @Sharded(shardKey = "empno") // Sharding Key 설정
  class Employee {
      @Id // id, Mongodb 에서 자동으로 만들어주는 ID값
      private String id;
      @Field("empno") // field(column)
      @Indexed(name = "index_name") // index 설정
      private int empno;
  
      public Employee(int empno) {
          this.empno = empno;
      }
  }
  
  // Repository
  interface EmployeeRepository extends ReactiveMongoRepository<Employee, String> {
  }
  ```
- Repository 및 Entity 사용 예시  

## 참고
- 만약 arbiter 가 write concern 의 이유로 올라가지 않는다면
  - primary 에서 arbiter 제거, mongos 에서 `db.adminCommand({ setDefaultRWConcern: 1, defaultWriteConcern: { w: 1 } })` 로 조정
  - 이후 다시 primary 에서 arbiter 추가 `rs.addArb(...)`
- arbiter 에서 아래와 같은 에러가 지속적으로 날 수 있고 그냥 무시해도 괜찮다.
  - Arbiter 는 data 를 갖지 않으므로 op log 가 불필요함, 아래 에러는 oplog missing exception
```bash
{"t":{"$date":"2024-08-09T09:01:11.000+00:00"},"s":"W",  "c":"QUERY",    "id":23799,   "ctx":"ftdc","msg":"Aggregate command executor error","attr":{"error":{"code":26,"codeName":"NamespaceNotFound","errmsg":"Unable to retrieve storageStats in $collStats stage :: caused by :: Collection [local.oplog.rs] not found."},"stats":{},"cmd":{"aggregate":"oplog.rs","cursor":{},"pipeline":[{"$collStats":{"storageStats":{"waitForLock":false,"numericOnly":true}}}],"$db":"local"}}}
```
