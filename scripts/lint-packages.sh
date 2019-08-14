#!/usr/bin/env bash

set -e -u

REPO_DIR=$(realpath "$(dirname "$0")/../")
PACKAGES_DIR="$REPO_DIR/packages"

lint_package() {
	local package_script
	local package_name

	package_script=$1
	package_name=$(basename "$(dirname "$package_script")")

	echo "================================================================"
	echo
	echo "Package: $package_name"
	echo -n "Syntax check: "

	local syntax_errors
	syntax_errors=$(bash -n "$package_script" 2>&1)

	if [ -n "$syntax_errors" ]; then
		echo "FAILED"
		echo
		echo "$syntax_errors"
		echo

		return 1
	else
		echo "OK"
	fi

	echo

	# Fields checking is done in subshell since we will source build.sh.
	(set +e +u
		local pkg_lint_error

		# Certain fields may be API-specific.
		# Using API 24 here.
		TERMUX_PKG_API_LEVEL=24

		. "$package_script"

		pkg_lint_error=false

		echo -n "TERMUX_PKG_HOMEPAGE: "
		if [ -n "$TERMUX_PKG_HOMEPAGE" ]; then
			if ! grep -qP '^https://.+' <<< "$TERMUX_PKG_HOMEPAGE"; then
				echo "NON-HTTPS"
			else
				echo "OK"
			fi
		else
			echo "NOT SET"
			pkg_lint_error=true
		fi

		echo -n "TERMUX_PKG_DESCRIPTION: "
		if [ -n "$TERMUX_PKG_DESCRIPTION" ]; then
			str_length=$(($(wc -c <<< "$TERMUX_PKG_DESCRIPTION") - 1))

			if [ $str_length -gt 100 ]; then
				echo "TOO LONG"
			else
				echo "OK"
			fi

			unset str_length
		else
			echo "NOT SET"
			pkg_lint_error=true
		fi

		echo -n "TERMUX_PKG_LICENSE: "
		if [ -n "$TERMUX_PKG_LICENSE" ]; then
			echo "OK"
		else
			echo "NOT SET"
			pkg_lint_error=true
		fi

		if [ -n "$TERMUX_PKG_API_LEVEL" ]; then
			echo -n "TERMUX_PKG_API_LEVEL: "

			if grep -qP '^[1-9][0-9]$' <<< "$TERMUX_PKG_API_LEVEL"; then
				if [ $TERMUX_PKG_API_LEVEL -lt 24 ] || [ $TERMUX_PKG_API_LEVEL -gt 28 ]; then
					echo "INVALID (allowed: number in range 24 - 28)"
					pkg_lint_error=true
				else
					echo "OK"
				fi
			else
				echo "INVALID (allowed: number in range 24 - 28)"
				pkg_lint_error=true
			fi
		fi

		echo -n "TERMUX_PKG_VERSION: "
		if [ -n "$TERMUX_PKG_VERSION" ]; then
			echo "OK"
		else
			echo "NOT SET"
			pkg_lint_error=true
		fi

		if [ -n "$TERMUX_PKG_REVISION" ]; then
			echo -n "TERMUX_PKG_REVISION: "

			if grep -qP '^[1-9](\d{1,8})?$' <<< "$TERMUX_PKG_REVISION"; then
				echo "OK"
			else
				echo "INVALID (allowed: number in range 1 - 999999999)"
				pkg_lint_error=true
			fi
		fi

		if [ -n "$TERMUX_PKG_SKIP_SRC_EXTRACT" ]; then
			echo -n "TERMUX_PKG_SKIP_SRC_EXTRACT: "

			if [ "$TERMUX_PKG_SKIP_SRC_EXTRACT" = "true" ] || [ "$TERMUX_PKG_SKIP_SRC_EXTRACT" = "false" ]; then
				echo "OK"
			else
				echo "INVALID (allowed: true / false)"
				pkg_lint_error=true
			fi
		fi

		if [ -n "$TERMUX_PKG_SRCURL" ]; then
			echo -n "TERMUX_PKG_SRCURL: "

			urls_ok=true
			for url in "${TERMUX_PKG_SRCURL[@]}"; do
				if [ -n "$url" ]; then
					if ! grep -qP '^https://.+' <<< "$url"; then
						echo "NON-HTTPS"
						urls_ok=false
						break
					fi
				else
					echo "NOT SET (one of the array elements)"
					urls_ok=false
					pkg_lint_error=true
					break
				fi
			done
			unset url

			if $urls_ok; then
				echo "OK"
			fi
			unset urls_ok

			echo -n "TERMUX_PKG_SHA256: "
			if [ -n "$TERMUX_PKG_SHA256" ]; then
				if [ "${#TERMUX_PKG_SRCURL[@]}" -eq "${#TERMUX_PKG_SHA256[@]}" ]; then
					sha256_ok=true

					for sha256 in "${TERMUX_PKG_SHA256[@]}"; do
						if ! grep -qP '^[0-9a-fA-F]{64}$' <<< "${sha256}"; then
							echo "MALFORMED (SHA-256 should contain 64 hexadecimal numbers)"
							sha256_ok=false
							pkg_lint_error=true
							break
						fi
					done
					unset sha256

					if $sha256_ok; then
						echo "OK"
					fi
					unset sha256_ok
				else
					echo "LENGTHS OF 'TERMUX_PKG_SRCURL' AND 'TERMUX_PKG_SHA256' ARE NOT EQUAL"
					pkg_lint_error=true
				fi
			else
				echo "NOT SET"
				pkg_lint_error=true
			fi
		else
			if [ "$TERMUX_PKG_SKIP_SRC_EXTRACT" != "true" ]; then
				echo "TERMUX_PKG_SRCURL: NOT SET (set TERMUX_PKG_SKIP_SRC_EXTRACT to 'true' if no sources downloaded)"
				pkg_lint_error=true
			fi
		fi

		if [ -n "$TERMUX_PKG_METAPACKAGE" ]; then
			echo -n "TERMUX_PKG_METAPACKAGE: "

			if [ "$TERMUX_PKG_METAPACKAGE" = "true" ] || [ "$TERMUX_PKG_METAPACKAGE" = "false" ]; then
				echo "OK"
			else
				echo "INVALID (allowed: true / false)"
				pkg_lint_error=true
			fi
		fi

		if [ -n "$TERMUX_PKG_ESSENTIAL" ]; then
			echo "TERMUX_PKG_ESSENTIAL: DISALLOWED FOR X11 PACKAGES"
			pkg_lint_error=true
			#if [ "$TERMUX_PKG_ESSENTIAL" = "true" ] || [ "$TERMUX_PKG_ESSENTIAL" = "false" ]; then
			#	echo "OK"
			#else
			#	echo "INVALID (allowed: true / false)"
			#	pkg_lint_error=true
			#fi
		fi

		if [ -n "$TERMUX_PKG_NO_STATICSPLIT" ]; then
			echo -n "TERMUX_PKG_NO_STATICSPLIT: "

			if [ "$TERMUX_PKG_NO_STATICSPLIT" = "true" ] || [ "$TERMUX_PKG_NO_STATICSPLIT" = "false" ]; then
				echo "OK"
			else
				echo "INVALID (allowed: true / false)"
				pkg_lint_error=true
			fi
		fi

		if [ -n "$TERMUX_PKG_BUILD_IN_SRC" ]; then
			echo -n "TERMUX_PKG_BUILD_IN_SRC: "

			if [ "$TERMUX_PKG_BUILD_IN_SRC" = "true" ] || [ "$TERMUX_PKG_BUILD_IN_SRC" = "false" ]; then
				echo "OK"
			else
				echo "INVALID (allowed: true / false)"
				pkg_lint_error=true
			fi
		fi

		if [ -n "$TERMUX_PKG_HAS_DEBUG" ]; then
			echo -n "TERMUX_PKG_HAS_DEBUG: "

			if [ "$TERMUX_PKG_HAS_DEBUG" = "true" ] || [ "$TERMUX_PKG_HAS_DEBUG" = "false" ]; then
				echo "OK"
			else
				echo "INVALID (allowed: true / false)"
				pkg_lint_error=true
			fi
		fi

		if [ -n "$TERMUX_PKG_PLATFORM_INDEPENDENT" ]; then
			echo -n "TERMUX_PKG_PLATFORM_INDEPENDENT: "

			if [ "$TERMUX_PKG_PLATFORM_INDEPENDENT" = "true" ] || [ "$TERMUX_PKG_PLATFORM_INDEPENDENT" = "false" ]; then
				echo "OK"
			else
				echo "INVALID (allowed: true / false)"
				pkg_lint_error=true
			fi
		fi

		if [ -n "$TERMUX_PKG_HOSTBUILD" ]; then
			echo -n "TERMUX_PKG_HOSTBUILD: "

			if [ "$TERMUX_PKG_HOSTBUILD" = "true" ] || [ "$TERMUX_PKG_HOSTBUILD" = "false" ]; then
				echo "OK"
			else
				echo "INVALID (allowed: true / false)"
				pkg_lint_error=true
			fi
		fi

		if [ -n "$TERMUX_PKG_FORCE_CMAKE" ]; then
			echo -n "TERMUX_PKG_FORCE_CMAKE: "

			if [ "$TERMUX_PKG_FORCE_CMAKE" = "true" ] || [ "$TERMUX_PKG_FORCE_CMAKE" = "false" ]; then
				echo "OK"
			else
				echo "INVALID (allowed: true / false)"
				pkg_lint_error=true
			fi
		fi

		if [ -n "$TERMUX_PKG_RM_AFTER_INSTALL" ]; then
			echo -n "TERMUX_PKG_RM_AFTER_INSTALL: "
			file_path_ok=true

			while read -r file_path; do
				[ -z "$file_path" ] && continue

				if grep -qP '^(\.\.)?/' <<< "$file_path"; then
					echo "INVALID (file path should be relative to prefix)"
					file_path_ok=false
					pkg_lint_error=true
					break
				fi
			done <<< "$TERMUX_PKG_RM_AFTER_INSTALL"
			unset file_path

			if $file_path_ok; then
				echo "OK"
			fi
			unset file_path_ok
		fi

		if [ -n "$TERMUX_PKG_CONFFILES" ]; then
			echo -n "TERMUX_PKG_CONFFILES: "
			file_path_ok=true

			while read -r file_path; do
				[ -z "$file_path" ] && continue

				if grep -qP '^(\.\.)?/' <<< "$file_path"; then
					echo "INVALID (file path should be relative to prefix)"
					file_path_ok=false
					pkg_lint_error=true
					break
				fi
			done <<< "$TERMUX_PKG_CONFFILES"
			unset file_path

			if $file_path_ok; then
				echo "OK"
			fi
			unset file_path_ok
		fi

		if $pkg_lint_error; then
			exit 1
		else
			exit 0
		fi
	)

	local ret=$?

	echo

	return "$ret"
}

for package_script in "$PACKAGES_DIR"/*/build.sh; do
	lint_package "$package_script" || exit 1
done
