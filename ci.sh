#!/usr/bin/env bash

set -eu

THREADS=${THREADS:-$(($(nproc 2>/dev/null) + 1))}
TEST_REPEATS=5

GIT_CI_DIR=git-ci

run_until_success () {
	runs="$1"; shift
	for (( n=0; n<runs; n++ ))
	do
		"$@" && return 0
	done
	return 1
}

build_test_branch () {
	git clean -dff -e "$GIT_CI_DIR"/ || return 3
	git reset --hard origin/"$1" || return 3
	git submodule update --init || return 3

	make -j "$THREADS" configure || return 1
	./configure || return 1
	make -j "$THREADS" all || return 1

	for patchfile in "$GIT_CI_DIR"/*.diff "$GIT_CI_DIR"/"$1"/*.diff
	do
		if [[ -r "$patchfile" ]]
		then
			patch -p1 <"$patchfile" || return 2
		fi
	done

	(
		cd t || return 2
		make DEFAULT_TEST_TARGET=prove GIT_TEST_OPTS='-i -l --tee' GIT_PROVE_OPTS="--jobs $THREADS" all

		for line in $(grep -lv 0 test-results/*.exit)
		do
			test=$(basename "$line" .exit)
			run_until_success "$TEST_REPEATS" ./"$test".sh -i -l --tee || return 1
		done
	) || return $?

	git clean -dff -e "$GIT_CI_DIR"/ || return 3
	git reset --hard || return 3
}

rc=0

git fetch

built_something=
for branch in $(git config --get-all git-ci.branch)
do
	new_hash=$(git rev-parse origin/"$branch")
	if [[ "$new_hash" != "$(git config "git-ci.${branch}.last-success")" ]]
	then
		date
		echo "Building origin/$branch ($new_hash)"
		if time build_test_branch "$branch"
		then
			git config "git-ci.${branch}.last-success" "$new_hash"
		else
			echo "Failed building origin/$branch"
			echo "Failing hash was $new_hash"
			echo "Last success on this branch was $(git config "git-ci.${branch}.last-success")"
			rc=1
		fi
		built_something=yes
		date
		echo "Finished building origin/$branch"
	else
		echo "Skipping origin/$branch ($new_hash)"
		echo "Already verified $(git config "git-ci.${branch}.last-success")"
	fi
done

exit "$rc"
