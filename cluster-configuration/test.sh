#!/bin/bash -e

files=$(ls values/*.yaml)



git stash
for f in $files; do
    output="/tmp/$(basename $f).before"
    helm template test . --values $f > $output
done

git stash pop
for f in $files; do
    output="/tmp/$(basename $f).after"
    helm template test . --values $f > $output
done

for f in $files; do
    output="/tmp/$(basename $f)"

    echo
    echo
    echo "------------- diff for $f -------------"
    echo
    set +e
    diff $output.before $output.after
    [[ $? -gt 0 ]] || echo "No diff"
    set -e
done
