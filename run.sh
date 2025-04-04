#!/bin/sh

nop=./sample.d/no-filter.wat
swt=./sample.d/starts-with-time.wat

sample_log(){
	echo 1970
	echo '2025-04-04T01:12:38.0Z INFO test log'
	echo 'time:2025-04-04T01:12:38.0Z\tlevel:INFO\tmsg:helo'
	echo '2025-04-04T01:12:38.1Z INFO test log 2'
	echo 'time:2025-04-04T01:12:38.1Z\tlevel:INFO\tmsg:wrld'
}

echo log using nop filter
sample_log |
	ENV_WAT_FILENAME=$nop ./LogFilterWasm |
	bat --language=log

echo
echo 'log using (too) simple filtering'
sample_log |
	ENV_WAT_FILENAME=$swt ./LogFilterWasm |
	bat --language=log
