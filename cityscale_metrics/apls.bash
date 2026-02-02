declare -a arr=(8 9 19 28 29 39 48 49 59 68 69 79 88 89 99 108 109 119 128 129 139 148 149 159 168 169 179)

dir=$1
mkdir -p "../$dir/results/apls"

echo "$dir"

for i in "${arr[@]}"; do
  if test -f "../${dir}/graph/${i}.p"; then
    echo "========================${i}======================"

    # GT: official-mode (refine gt graph on /mnt/data, absolute path)
    python3 ./apls/convert.py "/mnt/data/datasets/cityscale/20cities/region_${i}_refine_gt_graph.p" gt.json
    # Pred graph
    python3 ./apls/convert.py "../${dir}/graph/${i}.p" prop.json

    # Go must run in ./apls (where go.mod exists)
    ( cd ./apls && go run . ../gt.json ../prop.json "../../${dir}/results/apls/${i}.txt" cityscale )
  else
    echo "[SKIP] missing pred graph: ../${dir}/graph/${i}.p"
  fi
done

python3 apls.py --dir "$dir"
