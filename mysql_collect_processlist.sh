#!/bin/bash

#<<<<<<<< 需要修改的参数 <<<<<<<<<
# 设置 PATH，添加 mysql 所在路径（ whereis mysql ）
# 兼容ci，如果有环境变量，优先使用环境变量，否则使用默认值
MYSQL_PATH="${MYSQL_PATH:-/usr/bin/}"
export PATH=$MYSQL_PATH:$PATH
#MySQL连接参数
MYSQL_HOST="${MYSQL_HOST:-localhost}"
MYSQL_PORT="${MYSQL_PORT:-3306}"
MYSQL_USER="${MYSQL_USER:-root}"
MYSQL_PWD="${MYSQL_PWD:-}" # 替换为实际密码
export MYSQL_PWD=$MYSQL_PWD
MYSQL_DATABASE="${MYSQL_DATABASE:-mysql}"
#>>>>>>>>>> 需要修改的参数 >>>>>>>>

#echo "当前文件名:"$0 # 如果是绝对路径，会直接打印；而不是文件名
script_path=$(readlink -f "$0")
# 获取当前脚本的名称（不包含路径）
script_name=$(basename "$0")
#echo $script_name
# 获取当前脚本的目录
script_dir=$(dirname "$script_path")

LOG_FILE="$script_dir/processlist.log"

MAX_LOG_SIZE=$((1024 * 1024 * 1024)) # 1GB，纯文本的压缩率较高（测试 2.8GB-->19MB，压缩率约 99%），如果觉得小了，可以自行调整

# 获取当前时间戳（用于日志分割）
CURRENT_HOUR=$(date +"%Y%m%d-%H")      # 精确到小时

batchid=$(date +"%Y%m%d_%H%M%S_%N")

# 日志记录函数
# 函数名: log_message
# 描述: 将日志消息输出到指定日志文件
# 参数: 
#   $1 - 日志级别 (INFO, WARNING, ERROR)
#   $2 - 日志消息内容
log_message() {
    # 确保日志目录存在
    # 定义日志文件路径
    SHELL_LOG_FILE="$script_dir/debug.log"

    local log_level=$1
    local message=$2
    echo "$(date '+%Y-%m-%d %H:%M:%S.%N')|$batchid|[$log_level]|$message" | tee -a "$SHELL_LOG_FILE"
}

# 检查当前脚本进程是否已存在的函数
check_existing_process() {
    LOCK_FILE="$script_dir/${0##*/}.lock" # 根据脚本名称生成锁文件
    exec 9>"$LOCK_FILE" # 将文件描述符9与锁文件关联

    if flock -n 9; then # 非阻塞模式尝试获取排他锁
        # 设置 trap：无论在什么情况下退出，都释放锁并删除锁文件
        trap 'flock -u 9; rm -f "$LOCK_FILE"; exit' INT TERM EXIT
        #log_message "INFO" "获取锁成功，进程 $script_name 不存在，开始执行脚本。"
    else
        log_message "WARNING" "获取锁失败，进程 $script_name 已在运行中，退出脚本。"
        exit 1
    fi
}


# 检查并分割日志文件
check_and_split_log() {
    # 确保日志目录存在
    mkdir -p "$script_dir/logs"

    # 按照日志文件时间（每小时）分割文件
    if [ ! -f "$LOG_FILE" ] || [ "$(date -r "$LOG_FILE" +"%Y%m%d-%H")" != "$CURRENT_HOUR" ]; then
        if [ -f "$LOG_FILE" ]; then
            file_time=$(date -r "$LOG_FILE" +"%Y%m%d-%H")
            gzip_file_name="$script_dir/logs/processlist-${file_time}.log.gz"
            # 分割并压缩日志文件
            gzip -c "$LOG_FILE" > "$gzip_file_name"
            log_message "INFO" "按小时分割日志，日志已分割并压缩为 $gzip_file_name 。"

            # 清空原日志文件
            true > "$LOG_FILE"
        fi
    fi

    # 按照日志文件大小分割文件
    if [ -f "$LOG_FILE" ]; then
        # 检查文件大小
        file_size=$(stat -c%s "$LOG_FILE")
        if [ "$file_size" -ge "$MAX_LOG_SIZE" ]; then
            # 获取文件创建时间（精确到秒）
            file_time=$(date -r "$LOG_FILE" +"%Y%m%d-%H%M%S")
            gzip_file_name="$script_dir/logs/processlist-${file_time}.log.gz"
            # 分割并压缩日志文件
            gzip -c "$LOG_FILE" > "$gzip_file_name"
            log_message "INFO" "日志大小达到阈值[$MAX_LOG_SIZE]，日志已分割并压缩为 $gzip_file_name 。"

            # 清空原日志文件
            true > "$LOG_FILE"
        fi
    fi
}

# 执行MySQL查询并记录到日志文件
execute_query() {
    log_message "INFO" "开始查询数据库..."

    # 查询 information_schema.processlist
    #ERROR_OUTPUT=$(mysql -h "$MYSQL_HOST" -P "$MYSQL_PORT" -u "$MYSQL_USER" --silent --skip-column-names -B -e "SELECT * from information_schema.processlist;" "$MYSQL_DATABASE"  2>&1  >> "$LOG_FILE" )
    # 为了能够正常捕获异常及进行换行符处理，不直接输出到文件
    ALL_OUTPUT=$(mysql -h "$MYSQL_HOST" -P "$MYSQL_PORT" -u "$MYSQL_USER" --silent --skip-column-names -B -e "SELECT now(),ID,USER,HOST,DB,COMMAND,TIME,STATE,INFO from information_schema.processlist ORDER BY time DESC;" "$MYSQL_DATABASE"  2>&1 )
    EXIT_STATUS=$?
    #echo "ALL_OUTPUT:"$ALL_OUTPUT
    #echo "EXIT_STATUS:"$EXIT_STATUS

    # 检查执行状态：如果没有异常，这个就是输出的结果；如果有异常，就是报错信息
    if [ $EXIT_STATUS -eq 0 ]; then
        log_message "INFO" "SQL命令执行成功。"
        echo "$ALL_OUTPUT" | tr '\t' '|' >> "$LOG_FILE"
    else
        ERROR_OUTPUT=$ALL_OUTPUT
        log_message "ERROR" "SQL命令执行失败，错误信息为：$ERROR_OUTPUT"
        # 根据错误信息进行更精细化的判断和处理
        if echo "$ERROR_OUTPUT" | grep -q "ERROR 2002 (HY000): Can't connect to local MySQL server through socket "; then
            log_message "ERROR" "错误：无法连接到 MySQL 服务器，请检查MySQL服务是否正常运行。"
        elif echo "$ERROR_OUTPUT" | grep -q "ERROR 2005 (HY000): Unknown MySQL server host "; then
            log_message "ERROR" "错误：host 认证失败，请检查。"
        elif echo "$ERROR_OUTPUT" | grep -q "ERROR 1045 (28000): Access denied for user "; then
            log_message "ERROR" "错误：密码认证失败，请检查用户名和密码。"
        elif echo "$ERROR_OUTPUT" | grep -q "ERROR 1049 (42000): Unknown database "; then
            log_message "ERROR" "错误：数据库不存在，请检查。"
        elif echo "$ERROR_OUTPUT" | grep -q "ERROR 1040 (HY000): Too many connections"; then
            log_message "ERROR" "错误：数据库连接数已满。"
            # 可以在这里加入处理连接数满的代码，例如重试或终止空闲连接
        # ... 其他错误类型的判断和处理
        else
            log_message "ERROR" "错误：未知错误，详见报错信息。"
        fi
        exit 1
    fi

    log_message "INFO" "查询数据库结束。"
}

# 主函数
main() {
    log_message "INFO" "begin..."
    check_existing_process
    check_and_split_log
    execute_query
    log_message "INFO" "end!"
}

main
