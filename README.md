# mysql_collect_processlist

![GitHub Actions Workflow Status](https://img.shields.io/github/actions/workflow/status/yansheng836/mysql_collect_processlist/shell-ci.yml?style=flat&label=build%3A%20shell-ci) ![GitHub Actions Workflow Status](https://img.shields.io/github/actions/workflow/status/yansheng836/mysql_collect_processlist/MySQL-ci-16.3.yml?style=flat&label=build%3A%20MySQL-ci-16.3) ![GitHub Actions Workflow Status](https://img.shields.io/github/actions/workflow/status/yansheng836/mysql_collect_processlist/MySQL-ci.yml?style=flat&label=build%3A%20MySQL-ci-10-17) ![GitHub commit activity](https://img.shields.io/github/commit-activity/m/yansheng836/mysql_collect_processlist) [![GitHub Issues](https://img.shields.io/github/issues/yansheng836/mysql_collect_processlist)](https://github.com/yansheng836/mysql_collect_processlist/issues) [![GitHub Pull Requests](https://img.shields.io/github/issues-pr/yansheng836/mysql_collect_processlist)](https://github.com/yansheng836/mysql_collect_processlist/pulls) [![GitHub Tag](https://img.shields.io/github/v/tag/yansheng836/mysql_collect_processlist)](https://github.com/yansheng836/mysql_collect_processlist/tags) [![GitHub Release](https://img.shields.io/github/v/release/yansheng836/mysql_collect_processlist)](https://github.com/yansheng836/mysql_collect_processlist/releases) ![GitHub Repo stars](https://img.shields.io/github/stars/yansheng836/mysql_collect_processlist) ![GitHub forks](https://img.shields.io/github/forks/yansheng836/mysql_collect_processlist) [![Codacy Badge](https://app.codacy.com/project/badge/Grade/4460db83948f4592ab825e8e900ec79f)](https://app.codacy.com/gh/yansheng836/mysql_collect_processlist/dashboard?utm_source=gh&utm_medium=referral&utm_content=&utm_campaign=Badge_grade) [![GitHub License](https://img.shields.io/github/license/yansheng836/mysql_collect_processlist)](https://github.com/yansheng836/mysql_collect_processlist/blob/master/LICENSE.txt)

这是一个纯脚本工具，用于从MySQL的`information_schema.processlist`视图中定期收集数据并保存到本地日志文件。支持MYSQL8.0.43版本。

**相关背景**：

1. 某个慢SQL打满内存，导致系统kill掉mysql的进程，进而导致mysql进程重启，没有现场排查不了具体原因。（即使开启了慢SQL日志，没有执行完也不会记录到数据库日志中）
2. 数据库连接数被打满，MYSQL相关监控数据丢失（因为也连不上数据库了），没有现场，不知道异常请求来源。

**特性**：

- 定期收集MySQL活动会话信息
- 支持通过定时任务配置收集频率
- 提供日志文件自动分割功能
- 包含丰富的日志分析示例

## 安装指南

拉取代码，修改参数，设置定时任务。

```shell
# 克隆代码
git clone git@github.com:yansheng836/mysql_collect_processlist.git
cd mysql_collect_processlist

# 修改必要参数(均以 MYSQL_ 开头，例如：MYSQL_PATH、MYSQL_HOST 等)
vi mysql_collect_processlist.sh

# 查路径
pwd

# crontab -e
# 每分钟执行
* * * * * pwd路径/mysql_collect_processlist.sh

# 如果需要更频繁，比如每5秒执行（可自行调整秒数）
* * * * * pwd路径/mysql_collect_processlist_gap_second.sh 5
```

## 日志文件内容

测试版本：mysql  Ver 8.0.43 for Linux on x86_64 (MySQL Community Server - GPL)

CI版本：

输出字段为：now(),ID,USER,HOST,DB,COMMAND,TIME,STATE,INFO

```plain
2025-09-09 14:44:02|42|root|localhost|mysql|Query|0|executing|SELECT now(),ID,USER,HOST,DB,COMMAND,TIME,STATE,INFO from information_schema.processlist
2025-09-09 14:44:02|5|event_scheduler|localhost|NULL|Daemon|8000|Waiting on empty queue|NULL
```

## 日志分析参考

### 1.简单检索

```shell
# cat/more/less/grep 
grep 'executing' processlist.log

# 查找具体时间的相关日志
grep '2025-09-04 12:59' processlist.log

# 在归档日志中，查找具体时间的相关日志
zless logs/processlist-20250904-12.log.gz  | grep '2025-09-04 12:59'
```

### 2.统计不同状态的语句的数量

```shell
# 第8列是状态：state
awk -F '|' '{print $8}' processlist.log | sort | uniq -c
      1 executing
      1 Waiting on empty queue
```

### 3.按照时间统计

```shell
# 按天统计
awk -F '|' '{print $1}' processlist.log | cut -d ' ' -f1 | sort | uniq -c
      2 2025-09-09
# 按小时统计
awk -F '[| ]' '{print $1 " " $2}' processlist.log | cut -d: -f1 | sort | uniq -c
      2 2025-09-09 14
# 按分钟统计
awk -F '[| ]' '{print $1 " " $2}' processlist.log | cut -d: -f1-2 | sort | uniq -c
      2 2025-09-09 14:44
```

## 注意事项

1. 在业务繁忙的数据库上使用时，需要注意日志文件可能会快速增长，建议在特殊情况下短暂使用，并密切关注磁盘空间。
2. `info`字段的长度受MySQL常量`PROCESS_LIST_INFO_WIDTH`限制，默认为65535（写死在源码中），超出部分会被截断。（足以满足绝大多数场景。）
3. 账号权限问题，可不使用mysql。推荐最小权限：[创建空库，]创建普通用户，授予`PROCESS`权限即可。
      ```sql
      -- CREATE DATABASE processlist_db;
      GRANT PROCESS ON *.* TO 'processlist_user'@'hostname';
      ```

## 贡献

欢迎提交bug报告或功能需求：

GitHub：<https://github.com/yansheng836/mysql_collect_processlist/issues>

Gitee：<https://gitee.com/yansheng0083/mysql_collect_processlist/issues>

## License

使用 MIT License。有关详细信息，请参阅 [LICENSE.txt](./LICENSE.txt) 文件。
