#!/usr/bin/env bash

set -eu

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
BRANCHES=(pu next master maint)
declare -A OCCASIONAL_FAILURE_ATTEMPTS=([t1410]=50 [t9167]=100)

run_until_success () {
	runs="$1"; shift
	for (( n=0; n<runs; n++ ))
	do
		"$@" && return 0
	done
	return 1
}

build_test_branch () {
	git clean -dff || return 3
	git reset --hard origin/"$1" || return 3

	make -j4 configure || return 1
	./configure || return 1
	make -j4 all || return 1

	patch -p1 <"$SCRIPT_DIR"/patch.diff || return 2
	cd t || return 2
	make -k DEFAULT_TEST_TARGET=prove GIT_PROVE_OPTS='--jobs 4' GIT_SKIP_TESTS="${!OCCASIONAL_FAILURE_ATTEMPTS[*]}" all || return 1

	for test_script in "${!OCCASIONAL_FAILURE_ATTEMPTS[@]}"
	do
		full_script_name=("$test_script"-*.sh)
		run_until_success "${OCCASIONAL_FAILURE_ATTEMPTS["$test_script"]}" ./"${full_script_name[0]}" -i || return 1
	done
	cd -
}


# Initialize the array of hashes.  Set everything to blank strings so we do a
# build first time around.
declare -A hashes
for branch in "${BRANCHES[@]}"
do
	hashes["$branch"]=
done

while :
do
	git fetch

	built_something=
	for branch in "${BRANCHES[@]}"
	do
		new_hash=$(git rev-parse origin/"$branch")
		if [[ "$new_hash" != "${hashes["$branch"]}" ]]
		then
			date
			echo "Building origin/$branch ($new_hash)"
			if ! build_test_branch "$branch"
			then
				echo "Failed building origin/$branch"
				echo "Failing hash was $new_hash"
				echo "Last success on this branch was ${hashes["$branch"]}"
				exit 1
			fi
			built_something=yes
			hashes["$branch"]=$new_hash
			date
			echo "Finished building origin/$branch"
		fi
	done

	if [[ -z $built_something ]]
	then
		# Haven't built anything.  Sleep for 10 minutes to avoid
		# tightlooping.
		echo "Sleeping for 10 minutes"
		sleep 600
		date
	fi
done
