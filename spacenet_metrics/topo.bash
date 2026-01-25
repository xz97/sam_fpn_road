dir=$1
# 必须在 spacenet_metrics/topo 下运行，否则 ../../save 解析错误
(cd topo && python3 main.py -savedir "$dir")
(cd topo && python3 ../topo.py -savedir "$dir")
