# vi:filetype=perl

use lib 'lib';
use Test::Nginx::Socket;

repeat_each(10);

plan tests => repeat_each() * 2 * blocks() + 2 * repeat_each() * 3;

no_long_string();

run_tests();

#no_diff();

__DATA__

=== TEST 1: sanity
db init:

create table cats (id integer, name text);
insert into cats (id) values (2);
insert into cats (id, name) values (3, 'bob');

--- http_config
    upstream backend {
        drizzle_server 127.0.0.1:3306 dbname=test
             password=some_pass user=monty protocol=mysql;
    }
--- config
    location /mysql {
        drizzle_pass backend;
        #drizzle_dbname $dbname;
        drizzle_query 'select * from cats';
        rds_json on;
    }
--- request
GET /mysql
--- response_headers_like
X-Resty-DBD-Module: ngx_drizzle \d+\.\d+\.\d+
Content-Type: application/json
--- response_body chomp
[{"id":2,"name":null},{"id":3,"name":"bob"}]
--- timeout: 15



=== TEST 2: keep-alive
db init:

create table cats (id integer, name text);
insert into cats (id) values (2);
insert into cats (id, name) values (3, 'bob');

--- http_config
    upstream backend {
        drizzle_server localhost dbname=test
             password=some_pass user=monty protocol=mysql;
        drizzle_keepalive max=1;
    }
--- config
    location /mysql {
        drizzle_pass backend;
        #drizzle_dbname $dbname;
        drizzle_query 'select * from cats';
        rds_json on;
    }
--- request
GET /mysql
--- response_body chop
[{"id":2,"name":null},{"id":3,"name":"bob"}]



=== TEST 3: update
db init:

create table cats (id integer, name text);
insert into cats (id) values (2);
insert into cats (id, name) values (3, 'bob');

--- http_config
    upstream backend {
        drizzle_server 127.0.0.1:3306 dbname=test
             password=some_pass user=monty protocol=mysql;
        drizzle_keepalive mode=single max=2 overflow=reject;
    }
--- config
    location /mysql {
        drizzle_pass backend;
        #drizzle_dbname $dbname;
        drizzle_query "update cats set name='bob' where name='bob'";
        rds_json on;
    }
--- request
GET /mysql
--- response_body chop
{"errcode":0,"errstr":"Rows matched: 1  Changed: 0  Warnings: 0"}



=== TEST 4: select empty result
db init:

create table cats (id integer, name text);
insert into cats (id) values (2);
insert into cats (id, name) values (3, 'bob');

--- http_config
    upstream backend {
        drizzle_server 127.0.0.1:3306 dbname=test
             password=some_pass user=monty protocol=mysql;
        drizzle_keepalive mode=multi max=1;
    }
--- config
    location /mysql {
        drizzle_pass backend;
        drizzle_query "select * from cats where name='tom'";
        rds_json on;
    }
--- request
GET /mysql
--- response_body chop
[]



=== TEST 5: update & no module header
db init:

create table cats (id integer, name text);
insert into cats (id) values (2);
insert into cats (id, name) values (3, 'bob');

--- http_config
    upstream backend {
        drizzle_server 127.0.0.1:3306 dbname=test
             password=some_pass user=monty protocol=mysql;
        drizzle_keepalive mode=single max=2 overflow=reject;
    }
--- config
    location /mysql {
        if ($arg_name ~ '[^A-Za-z0-9]') {
            return 400;
        }

        drizzle_pass backend;
        drizzle_module_header off;
        drizzle_query "update cats set name='$arg_name' where name='$arg_name'";

        rds_json on;
    }
--- request
GET /mysql?name=bob
--- response_headers
X-Resty-DBD-Module: 
Content-Type: application/json
--- response_body chop
{"errcode":0,"errstr":"Rows matched: 1  Changed: 0  Warnings: 0"}



=== TEST 6: invalid SQL
--- http_config
    upstream backend {
        drizzle_server 127.0.0.1:3306 dbname=test
             password=some_pass user=monty protocol=mysql;
    }
--- config
    location /mysql {
        drizzle_pass backend;
        drizzle_module_header off;
        drizzle_query "select '32";
        rds_json on;
    }
--- response_headers
X-Resty-DBD-Module:
Content-Type: text/html
--- request
GET /mysql
--- error_code: 500
--- response_body_like: 500 Internal Server Error



=== TEST 7: single row, single col
--- http_config
    upstream backend {
        drizzle_server 127.0.0.1:3306 dbname=test
             password=some_pass user=monty protocol=mysql;
    }
--- config
    location /test {
        echo_location /mysql "drop table if exists singles";
        echo;
        echo_location /mysql "create table singles (name varchar(15));";
        echo;
        echo_location /mysql "insert into singles values ('marry');";
        echo;
        echo_location /mysql "select * from singles;";
        echo;
    }
    location /mysql {
        drizzle_pass backend;
        drizzle_module_header off;
        drizzle_query $query_string;
        rds_json on;
    }
--- request
GET /test
--- response_body
{"errcode":0}
{"errcode":0}
{"errcode":0,"affected_rows":1}
[{"name":"marry"}]
--- skip_nginx: 2: < 0.7.46



=== TEST 8: floating number and insert id
--- http_config
    upstream backend {
        drizzle_server 127.0.0.1:3306 dbname=test
             password=some_pass user=monty protocol=mysql;
    }
--- config
    location /test {
        echo_location /mysql "drop table if exists foo";
        echo;
        echo_location /mysql "create table foo (id serial not null, primary key (id), val real);";
        echo;
        echo_location /mysql "insert into foo (val) values (3.1415926);";
        echo;
        echo_location /mysql "select * from foo;";
        echo;
    }
    location /mysql {
        drizzle_pass backend;
        drizzle_module_header off;
        drizzle_query $query_string;
        rds_json on;
    }
--- request
GET /test
--- response_body
{"errcode":0}
{"errcode":0}
{"errcode":0,"insert_id":1,"affected_rows":1}
[{"id":1,"val":3.1415926}]
--- skip_nginx: 2: < 0.7.46



=== TEST 9: text blob field
--- http_config
    upstream backend {
        drizzle_server 127.0.0.1:3306 dbname=test
             password=some_pass user=monty protocol=mysql;
    }
--- config
    location /test {
        echo_location /mysql "drop table if exists foo";
        echo;
        echo_location /mysql "create table foo (id serial, body text);";
        echo;
        echo_location /mysql "insert into foo (body) values ('hello');";
        echo;
        echo_location /mysql "select * from foo;";
        echo;
    }
    location /mysql {
        drizzle_pass backend;
        drizzle_module_header off;
        drizzle_query $query_string;
        rds_json on;
    }
--- request
GET /test
--- response_body
{"errcode":0}
{"errcode":0}
{"errcode":0,"insert_id":1,"affected_rows":1}
[{"id":1,"body":"hello"}]
--- skip_nginx: 2: < 0.7.46



=== TEST 10: bool blob field
--- http_config
    upstream backend {
        drizzle_server 127.0.0.1:3306 dbname=test
             password=some_pass user=monty protocol=mysql;
    }
--- config
    location /test {
        echo_location /mysql "drop table if exists foo";
        echo;
        echo_location /mysql "create table foo (id serial, flag bool);";
        echo;
        echo_location /mysql "insert into foo (flag) values (true);";
        echo;
        echo_location /mysql "insert into foo (flag) values (false);";
        echo;
        echo_location /mysql "select * from foo order by id;";
        echo;
    }
    location /mysql {
        drizzle_pass backend;
        drizzle_module_header off;
        drizzle_query $query_string;
        rds_json on;
    }
--- request
GET /test
--- response_body
{"errcode":0}
{"errcode":0}
{"errcode":0,"insert_id":1,"affected_rows":1}
{"errcode":0,"insert_id":2,"affected_rows":1}
[{"id":1,"flag":1},{"id":2,"flag":0}]
--- skip_nginx: 2: < 0.7.46



=== TEST 11: bit field
--- http_config
    upstream backend {
        drizzle_server 127.0.0.1:3306 dbname=test
             password=some_pass user=monty protocol=mysql;
    }
--- config
    location /test {
        echo_location /mysql "drop table if exists foo";
        echo;
        echo_location /mysql "create table foo (id serial, flag bit);";
        echo;
        echo_location /mysql "insert into foo (flag) values (1);";
        echo;
        echo_location /mysql "insert into foo (flag) values (0);";
        echo;
        echo_location /mysql "select * from foo order by id;";
        echo;
    }
    location /mysql {
        drizzle_pass backend;
        drizzle_module_header off;
        drizzle_query $query_string;
        rds_json on;
    }
--- request
GET /test
--- response_body
{"errcode":0}
{"errcode":0}
{"errcode":0,"insert_id":1,"affected_rows":1}
{"errcode":0,"insert_id":2,"affected_rows":1}
[{"id":1,"flag":"\u0001"},{"id":2,"flag":"\u0000"}]
--- skip_nginx: 2: < 0.7.46



=== TEST 12: date type
--- http_config
    upstream backend {
        drizzle_server 127.0.0.1:3306 dbname=test
             password=some_pass user=monty protocol=mysql;
    }
--- config
    location /test {
        echo_location /mysql "drop table if exists foo";
        echo;
        echo_location /mysql "create table foo (id serial, created date);";
        echo;
        echo_location /mysql "insert into foo (created) values ('2007-05-24');";
        echo;
        echo_location /mysql "select * from foo";
        echo;
    }
    location /mysql {
        drizzle_pass backend;
        drizzle_module_header off;
        drizzle_query $query_string;
        rds_json on;
    }
--- request
GET /test
--- response_body
{"errcode":0}
{"errcode":0}
{"errcode":0,"insert_id":1,"affected_rows":1}
[{"id":1,"created":"2007-05-24"}]



=== TEST 13: strings need to be escaped
--- http_config
    upstream backend {
        drizzle_server 127.0.0.1:3306 dbname=test
             password=some_pass user=monty protocol=mysql;
    }
--- config
    location /test {
        echo_location /mysql "drop table if exists foo";
        echo;
        echo_location /mysql "create table foo (id serial, body char(25));";
        echo;
        echo_location /mysql "insert into foo (body) values ('a\\r\\nb\\b你好\Z');";
        echo;
        echo_location /mysql "select * from foo";
        echo;
    }
    location /mysql {
        drizzle_pass backend;
        drizzle_module_header off;
        drizzle_query $query_string;
        rds_json on;
    }
--- request
GET /test
--- response_body
{"errcode":0}
{"errcode":0}
{"errcode":0,"insert_id":1,"affected_rows":1}
[{"id":1,"body":"a\r\nb\b你好\u001a"}]



=== TEST 14: null values
--- http_config
    upstream backend {
        drizzle_server 127.0.0.1:3306 dbname=test
             password=some_pass user=monty protocol=mysql;
    }
--- config
    location /test {
        echo_location /mysql "drop table if exists foo";
        echo;
        echo_location /mysql "create table foo (id serial, name char(10), age integer);";
        echo;
        echo_location /mysql "insert into foo (name, age) values ('', null);";
        echo;
        echo_location /mysql "insert into foo (name, age) values (null, 0);";
        echo;
        echo_location /mysql "select * from foo order by id";
        echo;
    }
    location /mysql {
        drizzle_pass backend;
        drizzle_module_header off;
        drizzle_query $query_string;
        rds_json on;
    }
--- request
GET /test
--- response_body
{"errcode":0}
{"errcode":0}
{"errcode":0,"insert_id":1,"affected_rows":1}
{"errcode":0,"insert_id":2,"affected_rows":1}
[{"id":1,"name":"","age":null},{"id":2,"name":null,"age":0}]

