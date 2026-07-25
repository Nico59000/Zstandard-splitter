#!/bin/sh

# zstd-splitter.sh 3.0
# Create a tar stream, compress it with a selectable engine, split it into
# parts, join those parts, extract archives, and optionally enforce a strict
# SHA-256 integrity manifest.
#
# The command-line interface follows POSIX utility conventions: short options,
# getopts parsing, options before operands, and -- as the end-of-options marker.
# The implementation is written for POSIX /bin/sh. External compression and
# SHA-256 utilities are required for the selected features.

set -eu
LC_ALL=C
export LC_ALL

PROGRAM_NAME=${0##*/}
PROGRAM_VERSION=3.0
MANIFEST_FORMAT=1
SUFFIX_LENGTH=6
ACTION=
PART_SIZE=
ENGINE=zstd
ENGINE_SET=0
COMPRESSION_LEVEL=
THREADS=0
THREADS_SET=0
FORCE=0
STRICT_INTEGRITY=0
MANIFEST_FILE=
DESTINATION=
WORK_DIR=
TAR_PID=
COMPRESS_PID=
SPLIT_PID=
EXTRACT_PID=
LAST_ARCHIVE=

print_error()
{
    printf '%s: %s\n' "$PROGRAM_NAME" "$*" >&2
}

print_info()
{
    printf '%s\n' "$*"
}

list_engines()
{
    cat <<'EOF_ENGINES'
Supported compression engines:
  zstd   .tar.zst   command: zstd   levels: 1-22   threads: yes
  gzip   .tar.gz    command: gzip   levels: 1-9    threads: no
  bzip2  .tar.bz2   command: bzip2  levels: 1-9    threads: no
  xz     .tar.xz    command: xz     levels: 0-9    threads: yes
  lzma   .tar.lzma  command: xz     levels: 0-9    threads: yes
  lzip   .tar.lz    command: lzip   levels: 0-9    threads: no
  lzop   .tar.lzo   command: lzop   levels: 1-9    threads: no
  lz4    .tar.lz4   command: lz4    levels: 1-12   threads: no

Aliases accepted by -e:
  zst -> zstd, gz -> gzip, bz2 -> bzip2, lzo -> lzop

An engine is usable only when its external command is installed.
EOF_ENGINES
}

usage()
{
    cat <<EOF_USAGE
Usage:
  $PROGRAM_NAME -c -s SIZE [-e ENGINE] [-l LEVEL] [-T THREADS] [-i] [-f] SOURCE
  $PROGRAM_NAME -j [-i] [-m MANIFEST] [-f] PART
  $PROGRAM_NAME -x [-i] [-m MANIFEST] [-d DIRECTORY] [-f] INPUT
  $PROGRAM_NAME -v [-i] [-m MANIFEST] INPUT
  $PROGRAM_NAME -E
  $PROGRAM_NAME -h
  $PROGRAM_NAME

Actions:
  -c            Create a tar archive, compress it, and split it.
  -j            Join archive parts and verify the reconstructed stream.
  -x            Extract an archive, or join parts and then extract them.
  -v            Verify an archive or a set of parts without extracting it.
  -E            List supported compression engines.

Options:
  -e ENGINE     Compression engine used with -c. Default: zstd.
  -s SIZE       Maximum size of each part. Required with -c.
                SIZE may be a positive byte count or use K, M, G, T, or P,
                optionally followed by B or iB. Units are powers of 1024.
  -l LEVEL      Compression level. The accepted range depends on ENGINE.
  -T THREADS    Worker threads for zstd, xz, or lzma. Default: 0.
  -i            Enable strict SHA-256 integrity processing.
                Compression creates NAME.tar.EXT.manifest.sha256.
                Join, verify, and extract require and validate that manifest.
  -m MANIFEST   Use an explicit strict-integrity manifest with -j, -x, or -v.
  -d DIRECTORY  Extraction destination used with -x.
                Default: NAME.extracted beside the reconstructed archive.
  -f            Replace existing output without asking for confirmation.
                With -x, an existing destination is removed and recreated.
  -h            Display this help text and exit.
  --            End option processing.

Operands:
  SOURCE        One file, directory, or symbolic link to archive.
  PART          Any part named like NAME.tar.EXT.part.aaaaaa.
  INPUT         A supported compressed tar archive or any one of its parts.

Strict integrity validates three layers:
  1. A canonical SHA-256 inventory of the source content and tree structure.
  2. The SHA-256 and byte size of the complete compressed archive.
  3. The SHA-256 and byte size of every split part.

Examples:
  $PROGRAM_NAME -c -i -s 500M "/path/My directory"
  $PROGRAM_NAME -c -i -e xz -s 2GiB -l 6 -T 0 source-directory
  $PROGRAM_NAME -j -i "/path/My directory.tar.zst.part.aaaaac"
  $PROGRAM_NAME -x -i -d restored archive.tar.xz.part.aaaaaa
  $PROGRAM_NAME -v -i archive.tar.gz
  $PROGRAM_NAME -E

Compatibility aliases:
  $PROGRAM_NAME --help       is accepted as an alias for -h.
  $PROGRAM_NAME --engines    is accepted as an alias for -E.

When run without arguments, the script displays an interactive terminal menu.
EOF_USAGE
}

cleanup()
{
    trap - 0 1 2 3 15

    for cleanup_pid in "$TAR_PID" "$COMPRESS_PID" "$SPLIT_PID" "$EXTRACT_PID"
    do
        if [ -n "$cleanup_pid" ]; then
            kill "$cleanup_pid" 2>/dev/null || :
        fi
    done

    if [ -n "$WORK_DIR" ] && [ -d "$WORK_DIR" ]; then
        rm -rf "$WORK_DIR"
    fi
}

trap cleanup 0 1 2 3 15

require_command()
{
    if ! command -v "$1" >/dev/null 2>&1; then
        print_error "required command not found: $1"
        return 1
    fi
}

require_base_commands()
{
    for required_command in tar split cat mkdir rm mv dirname basename mkfifo awk wc
    do
        require_command "$required_command" || return 1
    done
}

require_integrity_commands()
{
    for required_command in sha256sum cmp readlink
    do
        require_command "$required_command" || return 1
    done
}

normalize_engine()
{
    case $1 in
        zstd|zst) printf '%s\n' zstd ;;
        gzip|gz) printf '%s\n' gzip ;;
        bzip2|bz2) printf '%s\n' bzip2 ;;
        xz) printf '%s\n' xz ;;
        lzma) printf '%s\n' lzma ;;
        lzip) printf '%s\n' lzip ;;
        lzop|lzo) printf '%s\n' lzop ;;
        lz4) printf '%s\n' lz4 ;;
        *) return 1 ;;
    esac
}

engine_extension()
{
    case $1 in
        zstd) printf '%s\n' zst ;;
        gzip) printf '%s\n' gz ;;
        bzip2) printf '%s\n' bz2 ;;
        xz) printf '%s\n' xz ;;
        lzma) printf '%s\n' lzma ;;
        lzip) printf '%s\n' lz ;;
        lzop) printf '%s\n' lzo ;;
        lz4) printf '%s\n' lz4 ;;
        *) return 1 ;;
    esac
}

engine_command()
{
    case $1 in
        zstd) printf '%s\n' zstd ;;
        gzip) printf '%s\n' gzip ;;
        bzip2) printf '%s\n' bzip2 ;;
        xz|lzma) printf '%s\n' xz ;;
        lzip) printf '%s\n' lzip ;;
        lzop) printf '%s\n' lzop ;;
        lz4) printf '%s\n' lz4 ;;
        *) return 1 ;;
    esac
}

engine_default_level()
{
    case $1 in
        zstd) printf '%s\n' 3 ;;
        gzip) printf '%s\n' 6 ;;
        bzip2) printf '%s\n' 9 ;;
        xz|lzma) printf '%s\n' 6 ;;
        lzip) printf '%s\n' 6 ;;
        lzop) printf '%s\n' 3 ;;
        lz4) printf '%s\n' 1 ;;
        *) return 1 ;;
    esac
}

engine_supports_threads()
{
    case $1 in
        zstd|xz|lzma) return 0 ;;
        *) return 1 ;;
    esac
}

validate_integer_range()
{
    integer_value=$1
    integer_min=$2
    integer_max=$3

    case $integer_value in
        ''|*[!0-9]*) return 1 ;;
    esac

    [ "$integer_value" -ge "$integer_min" ] && \
        [ "$integer_value" -le "$integer_max" ]
}

validate_engine_level()
{
    level_engine=$1
    level_value=$2

    case $level_engine in
        zstd) validate_integer_range "$level_value" 1 22 ;;
        gzip|bzip2|lzop) validate_integer_range "$level_value" 1 9 ;;
        xz|lzma|lzip) validate_integer_range "$level_value" 0 9 ;;
        lz4) validate_integer_range "$level_value" 1 12 ;;
        *) return 1 ;;
    esac
}

validate_nonnegative_integer()
{
    case $1 in
        ''|*[!0-9]*) return 1 ;;
        *) return 0 ;;
    esac
}

require_engine()
{
    compressor_command=$(engine_command "$1") || return 1
    require_command "$compressor_command"
}

make_work_dir()
{
    work_parent=$1
    old_umask=$(umask)
    umask 077

    work_index=0
    while :
    do
        WORK_DIR=$work_parent/.tar-splitter.$$.${work_index}
        if mkdir "$WORK_DIR" 2>/dev/null; then
            break
        fi
        work_index=$((work_index + 1))
        if [ "$work_index" -gt 100 ]; then
            umask "$old_umask"
            print_error "cannot create a temporary working directory in: $work_parent"
            return 1
        fi
    done

    umask "$old_umask"
}

confirm_replace()
{
    confirm_prompt=$1

    if [ "$FORCE" -eq 1 ]; then
        return 0
    fi

    if [ ! -t 0 ]; then
        print_error "$confirm_prompt Use -f to permit replacement."
        return 1
    fi

    printf '%s [y/N] ' "$confirm_prompt" >&2
    IFS= read -r confirm_answer || return 1

    case $confirm_answer in
        y|Y|yes|YES|Yes) return 0 ;;
        *) return 1 ;;
    esac
}

size_to_bytes()
{
    size_input=$1

    awk -v value="$size_input" '
        BEGIN {
            if (value !~ /^[1-9][0-9]*([KkMmGgTtPp]([iI]?[bB])?)?$/) {
                exit 1
            }
            number = value
            sub(/[KkMmGgTtPp].*$/, "", number)
            suffix = value
            sub(/^[0-9]+/, "", suffix)
            suffix = toupper(suffix)
            sub(/IB$/, "", suffix)
            sub(/B$/, "", suffix)
            multiplier = 1
            if (suffix == "K") multiplier = 1024
            else if (suffix == "M") multiplier = 1024 ^ 2
            else if (suffix == "G") multiplier = 1024 ^ 3
            else if (suffix == "T") multiplier = 1024 ^ 4
            else if (suffix == "P") multiplier = 1024 ^ 5
            else if (suffix != "") exit 1
            bytes = number * multiplier
            if (bytes < 1) exit 1
            printf "%.0f\n", bytes
        }
    '
}

file_size()
{
    wc -c <"$1" | awk '{print $1}'
}

sha256_file()
{
    sha256sum "$1" | awk '{print $1}'
}

sha256_stream()
{
    sha256sum | awk '{print $1}'
}

encode_manifest_text()
{
    ZSS_ENCODE_VALUE=$1
    export ZSS_ENCODE_VALUE
    awk 'BEGIN {
        value = ENVIRON["ZSS_ENCODE_VALUE"]
        gsub(/%/, "%25", value)
        gsub(/\t/, "%09", value)
        gsub(/\r/, "%0D", value)
        gsub(/\n/, "%0A", value)
        printf "%s", value
    }'
    unset ZSS_ENCODE_VALUE
}

manifest_walk()
{
    walk_actual=$1
    walk_relative=$2
    walk_output=$3
    walk_encoded=$(encode_manifest_text "$walk_relative")

    if [ -L "$walk_actual" ]; then
        walk_hash=$(readlink "$walk_actual" | sha256_stream) || return 1
        walk_size=$(readlink "$walk_actual" | wc -c | awk '{print $1}') || return 1
        printf 'source\tL\t%s\t%s\t%s\n' \
            "$walk_hash" "$walk_size" "$walk_encoded" >>"$walk_output"
        return 0
    fi

    if [ -f "$walk_actual" ]; then
        walk_hash=$(sha256_file "$walk_actual") || return 1
        walk_size=$(file_size "$walk_actual") || return 1
        printf 'source\tF\t%s\t%s\t%s\n' \
            "$walk_hash" "$walk_size" "$walk_encoded" >>"$walk_output"
        return 0
    fi

    if [ -d "$walk_actual" ]; then
        printf 'source\tD\t-\t0\t%s\n' "$walk_encoded" >>"$walk_output"

        for walk_child in \
            "$walk_actual"/* \
            "$walk_actual"/.[!.]* \
            "$walk_actual"/..?*
        do
            if [ ! -e "$walk_child" ] && [ ! -L "$walk_child" ]; then
                continue
            fi
            walk_child_name=${walk_child##*/}
            manifest_walk "$walk_child" "$walk_relative/$walk_child_name" \
                "$walk_output" || return 1
        done
        return 0
    fi

    print_error "strict integrity does not support this filesystem object: $walk_actual"
    return 1
}

generate_source_records_for_source()
{
    record_source=$1
    record_root=$2
    record_output=$3
    : >"$record_output"
    manifest_walk "$record_source" "$record_root" "$record_output"
}

generate_source_records_for_directory_contents()
{
    record_directory=$1
    record_output=$2
    : >"$record_output"

    for record_child in \
        "$record_directory"/* \
        "$record_directory"/.[!.]* \
        "$record_directory"/..?*
    do
        if [ ! -e "$record_child" ] && [ ! -L "$record_child" ]; then
            continue
        fi
        record_name=${record_child##*/}
        manifest_walk "$record_child" "$record_name" "$record_output" || return 1
    done
}

manifest_value()
{
    manifest_key=$1
    manifest_path=$2
    awk -F '\t' -v key="$manifest_key" '$1 == key { print $2; exit }' "$manifest_path"
}

manifest_record_count()
{
    manifest_tag=$1
    manifest_path=$2
    awk -F '\t' -v tag="$manifest_tag" '$1 == tag { count++ } END { print count + 0 }' \
        "$manifest_path"
}

validate_sha256_text()
{
    printf '%s\n' "$1" | awk '
        length($0) != 64 { exit 1 }
        $0 !~ /^[0-9a-f]+$/ { exit 1 }
    '
}

validate_manifest_structure()
{
    manifest_path=$1

    if [ ! -f "$manifest_path" ]; then
        print_error "strict-integrity manifest not found: $manifest_path"
        return 1
    fi

    manifest_header=$(awk 'NR == 1 { print; exit }' "$manifest_path")
    expected_manifest_header=$(printf 'zstd-splitter-manifest\t%s' "$MANIFEST_FORMAT")
    if [ "$manifest_header" != "$expected_manifest_header" ]; then
        print_error "unsupported or invalid manifest header: $manifest_path"
        return 1
    fi

    manifest_engine=$(manifest_value engine "$manifest_path")
    manifest_archive_sha=$(manifest_value archive_sha256 "$manifest_path")
    manifest_source_sha=$(manifest_value source_tree_sha256 "$manifest_path")
    manifest_archive_size=$(manifest_value archive_size "$manifest_path")
    manifest_source_count=$(manifest_value source_entry_count "$manifest_path")
    manifest_part_count=$(manifest_value part_count "$manifest_path")

    if [ -z "$manifest_engine" ] || [ -z "$manifest_archive_sha" ] || \
       [ -z "$manifest_source_sha" ] || [ -z "$manifest_archive_size" ] || \
       [ -z "$manifest_source_count" ] || [ -z "$manifest_part_count" ]; then
        print_error "manifest is missing required fields: $manifest_path"
        return 1
    fi

    validate_sha256_text "$manifest_archive_sha" || {
        print_error "invalid archive SHA-256 in manifest"
        return 1
    }
    validate_sha256_text "$manifest_source_sha" || {
        print_error "invalid source-tree SHA-256 in manifest"
        return 1
    }

    case $manifest_archive_size in ''|*[!0-9]*)
        print_error "invalid archive size in manifest"
        return 1
    esac
    case $manifest_source_count in ''|*[!0-9]*)
        print_error "invalid source entry count in manifest"
        return 1
    esac
    case $manifest_part_count in ''|*[!0-9]*|0)
        print_error "invalid part count in manifest"
        return 1
    esac

    manifest_source_records=$WORK_DIR/manifest-source-records
    manifest_part_records=$WORK_DIR/manifest-part-records
    awk -F '\t' '$1 == "source" { print }' "$manifest_path" >"$manifest_source_records"
    awk -F '\t' '$1 == "part" { print }' "$manifest_path" >"$manifest_part_records"

    actual_source_count=$(manifest_record_count source "$manifest_path")
    actual_part_count=$(manifest_record_count part "$manifest_path")
    actual_source_sha=$(sha256_file "$manifest_source_records")

    if [ "$actual_source_count" != "$manifest_source_count" ]; then
        print_error "source entry count does not match manifest records"
        return 1
    fi
    if [ "$actual_part_count" != "$manifest_part_count" ]; then
        print_error "part count does not match manifest records"
        return 1
    fi
    if [ "$actual_source_sha" != "$manifest_source_sha" ]; then
        print_error "source inventory records do not match their aggregate SHA-256"
        return 1
    fi

    awk -F '\t' '
        $1 == "part" {
            if ($2 !~ /^[a-z][a-z][a-z][a-z][a-z][a-z]$/) exit 1
            if ($3 !~ /^[0-9]+$/) exit 1
            if (length($4) != 64 || $4 !~ /^[0-9a-f]+$/) exit 1
        }
    ' "$manifest_path" || {
        print_error "invalid part record in manifest"
        return 1
    }

    return 0
}

write_integrity_manifest()
{
    wim_output_manifest=$1
    wim_source_records=$2
    wim_source_root=$3
    wim_archive_file=$4
    wim_temporary_prefix=$5
    wim_part_count=$6
    wim_part_size_bytes=$7

    wim_source_entry_count=$(awk 'END { print NR + 0 }' "$wim_source_records")
    wim_source_tree_sha=$(sha256_file "$wim_source_records")
    wim_archive_sha=$(sha256_file "$wim_archive_file")
    wim_archive_size=$(file_size "$wim_archive_file")
    wim_archive_name_encoded=$(encode_manifest_text "${wim_archive_file##*/}")
    wim_source_root_encoded=$(encode_manifest_text "$wim_source_root")

    {
        printf 'zstd-splitter-manifest\t%s\n' "$MANIFEST_FORMAT"
        printf 'tool_version\t%s\n' "$PROGRAM_VERSION"
        printf 'engine\t%s\n' "$ENGINE"
        printf 'archive_name\t%s\n' "$wim_archive_name_encoded"
        printf 'archive_size\t%s\n' "$wim_archive_size"
        printf 'archive_sha256\t%s\n' "$wim_archive_sha"
        printf 'source_root\t%s\n' "$wim_source_root_encoded"
        printf 'source_entry_count\t%s\n' "$wim_source_entry_count"
        printf 'source_tree_sha256\t%s\n' "$wim_source_tree_sha"
        printf 'part_count\t%s\n' "$wim_part_count"
        printf 'part_size_bytes\t%s\n' "$wim_part_size_bytes"
        cat "$wim_source_records"

        for wim_part in "$wim_temporary_prefix"??????
        do
            if [ ! -f "$wim_part" ]; then
                continue
            fi
            wim_suffix=${wim_part#"$wim_temporary_prefix"}
            wim_size=$(file_size "$wim_part")
            wim_sha=$(sha256_file "$wim_part")
            printf 'part\t%s\t%s\t%s\n' \
                "$wim_suffix" "$wim_size" "$wim_sha"
        done
        printf 'end\tmanifest\n'
    } >"$wim_output_manifest"
}

start_compressor()
{
    compressor_input=$1
    compressor_output=$2

    case $ENGINE in
        zstd) zstd -q -T"$THREADS" -"$COMPRESSION_LEVEL" -c \
            <"$compressor_input" >"$compressor_output" & ;;
        gzip) gzip -c -"$COMPRESSION_LEVEL" \
            <"$compressor_input" >"$compressor_output" & ;;
        bzip2) bzip2 -c -"$COMPRESSION_LEVEL" \
            <"$compressor_input" >"$compressor_output" & ;;
        xz) xz -c -"$COMPRESSION_LEVEL" -T"$THREADS" \
            <"$compressor_input" >"$compressor_output" & ;;
        lzma) xz --format=lzma -c -"$COMPRESSION_LEVEL" -T"$THREADS" \
            <"$compressor_input" >"$compressor_output" & ;;
        lzip) lzip -q -c -"$COMPRESSION_LEVEL" \
            <"$compressor_input" >"$compressor_output" & ;;
        lzop) lzop -q -c -"$COMPRESSION_LEVEL" \
            <"$compressor_input" >"$compressor_output" & ;;
        lz4) lz4 -q -z -c -"$COMPRESSION_LEVEL" \
            <"$compressor_input" >"$compressor_output" & ;;
        *) print_error "unsupported compression engine: $ENGINE"; return 1 ;;
    esac

    COMPRESS_PID=$!
}

start_decompressor()
{
    decompressor_engine=$1
    decompressor_input=$2
    decompressor_output=$3

    case $decompressor_engine in
        zstd) zstd -q -d -c "$decompressor_input" >"$decompressor_output" & ;;
        gzip) gzip -d -c "$decompressor_input" >"$decompressor_output" & ;;
        bzip2) bzip2 -d -c "$decompressor_input" >"$decompressor_output" & ;;
        xz) xz -d -c "$decompressor_input" >"$decompressor_output" & ;;
        lzma) xz --format=lzma -d -c "$decompressor_input" >"$decompressor_output" & ;;
        lzip) lzip -q -d -c "$decompressor_input" >"$decompressor_output" & ;;
        lzop) lzop -q -d -c "$decompressor_input" >"$decompressor_output" & ;;
        lz4) lz4 -q -d -c "$decompressor_input" >"$decompressor_output" & ;;
        *) print_error "unsupported compression engine: $decompressor_engine"; return 1 ;;
    esac

    COMPRESS_PID=$!
}

verify_archive_native()
{
    verify_engine=$1
    verify_file=$2

    case $verify_engine in
        zstd) zstd -q -t "$verify_file" ;;
        gzip) gzip -t "$verify_file" ;;
        bzip2) bzip2 -t "$verify_file" ;;
        xz) xz -t "$verify_file" ;;
        lzma) xz --format=lzma -t "$verify_file" ;;
        lzip) lzip -q -t "$verify_file" ;;
        lzop) lzop -q -t "$verify_file" ;;
        lz4) lz4 -q -t "$verify_file" ;;
        *) return 1 ;;
    esac
}

detect_engine_from_part()
{
    case $1 in
        *.tar.zst.part.[a-z][a-z][a-z][a-z][a-z][a-z]) printf '%s\n' zstd ;;
        *.tar.gz.part.[a-z][a-z][a-z][a-z][a-z][a-z]) printf '%s\n' gzip ;;
        *.tar.bz2.part.[a-z][a-z][a-z][a-z][a-z][a-z]) printf '%s\n' bzip2 ;;
        *.tar.xz.part.[a-z][a-z][a-z][a-z][a-z][a-z]) printf '%s\n' xz ;;
        *.tar.lzma.part.[a-z][a-z][a-z][a-z][a-z][a-z]) printf '%s\n' lzma ;;
        *.tar.lz.part.[a-z][a-z][a-z][a-z][a-z][a-z]) printf '%s\n' lzip ;;
        *.tar.lzo.part.[a-z][a-z][a-z][a-z][a-z][a-z]) printf '%s\n' lzop ;;
        *.tar.lz4.part.[a-z][a-z][a-z][a-z][a-z][a-z]) printf '%s\n' lz4 ;;
        *) return 1 ;;
    esac
}

detect_engine_from_archive()
{
    case $1 in
        *.tar.zst) printf '%s\n' zstd ;;
        *.tar.gz) printf '%s\n' gzip ;;
        *.tar.bz2) printf '%s\n' bzip2 ;;
        *.tar.xz) printf '%s\n' xz ;;
        *.tar.lzma) printf '%s\n' lzma ;;
        *.tar.lz) printf '%s\n' lzip ;;
        *.tar.lzo) printf '%s\n' lzop ;;
        *.tar.lz4) printf '%s\n' lz4 ;;
        *) return 1 ;;
    esac
}

archive_base_without_extension()
{
    case $1 in
        *.tar.zst) printf '%s\n' "${1%.tar.zst}" ;;
        *.tar.gz) printf '%s\n' "${1%.tar.gz}" ;;
        *.tar.bz2) printf '%s\n' "${1%.tar.bz2}" ;;
        *.tar.xz) printf '%s\n' "${1%.tar.xz}" ;;
        *.tar.lzma) printf '%s\n' "${1%.tar.lzma}" ;;
        *.tar.lz) printf '%s\n' "${1%.tar.lz}" ;;
        *.tar.lzo) printf '%s\n' "${1%.tar.lzo}" ;;
        *.tar.lz4) printf '%s\n' "${1%.tar.lz4}" ;;
        *) return 1 ;;
    esac
}

infer_manifest_for_archive()
{
    printf '%s.manifest.sha256\n' "$1"
}

infer_manifest_for_part()
{
    infer_prefix=${1%??????}
    infer_archive=${infer_prefix%.part.}
    infer_manifest_for_archive "$infer_archive"
}

resolve_manifest()
{
    resolve_input=$1
    resolve_kind=$2

    if [ -n "$MANIFEST_FILE" ]; then
        printf '%s\n' "$MANIFEST_FILE"
    elif [ "$resolve_kind" = part ]; then
        infer_manifest_for_part "$resolve_input"
    else
        infer_manifest_for_archive "$resolve_input"
    fi
}

validate_manifest_archive_identity()
{
    identity_manifest=$1
    identity_archive=$2
    identity_engine=$3

    manifest_engine=$(manifest_value engine "$identity_manifest")
    manifest_archive_name=$(manifest_value archive_name "$identity_manifest")
    actual_archive_name=$(encode_manifest_text "${identity_archive##*/}")

    if [ "$manifest_engine" != "$identity_engine" ]; then
        print_error "manifest engine mismatch: expected $identity_engine, found $manifest_engine"
        return 1
    fi
    if [ "$manifest_archive_name" != "$actual_archive_name" ]; then
        print_error "manifest archive name does not match: $identity_archive"
        return 1
    fi
}

validate_archive_against_manifest()
{
    archive_path=$1
    archive_engine=$2
    archive_manifest=$3

    validate_manifest_structure "$archive_manifest" || return 1
    validate_manifest_archive_identity "$archive_manifest" "$archive_path" \
        "$archive_engine" || return 1

    expected_archive_size=$(manifest_value archive_size "$archive_manifest")
    expected_archive_sha=$(manifest_value archive_sha256 "$archive_manifest")
    actual_archive_size=$(file_size "$archive_path")
    actual_archive_sha=$(sha256_file "$archive_path")

    if [ "$actual_archive_size" != "$expected_archive_size" ]; then
        print_error "compressed archive size mismatch"
        return 1
    fi
    if [ "$actual_archive_sha" != "$expected_archive_sha" ]; then
        print_error "compressed archive SHA-256 mismatch"
        return 1
    fi

    print_info "Strict archive SHA-256 verified: $actual_archive_sha"
}

validate_parts_against_manifest()
{
    selected_part=$1
    parts_manifest=$2
    input_prefix=${selected_part%??????}

    validate_manifest_structure "$parts_manifest" || return 1

    expected_part_count=$(manifest_value part_count "$parts_manifest")
    actual_part_count=0
    for actual_part in "$input_prefix"??????
    do
        if [ ! -f "$actual_part" ]; then
            continue
        fi
        actual_suffix=${actual_part#"$input_prefix"}
        case $actual_suffix in
            [a-z][a-z][a-z][a-z][a-z][a-z]) actual_part_count=$((actual_part_count + 1)) ;;
        esac
    done

    if [ "$actual_part_count" != "$expected_part_count" ]; then
        print_error "part count mismatch: expected $expected_part_count, found $actual_part_count"
        return 1
    fi

    part_records=$WORK_DIR/part-records
    awk -F '\t' '$1 == "part" { print }' "$parts_manifest" >"$part_records"

    while IFS="$(printf '\t')" read -r part_tag part_suffix expected_size expected_sha
    do
        [ "$part_tag" = part ] || continue
        part_path=$input_prefix$part_suffix
        if [ ! -f "$part_path" ]; then
            print_error "manifest part is missing: $part_path"
            return 1
        fi
        actual_size=$(file_size "$part_path")
        if [ "$actual_size" != "$expected_size" ]; then
            print_error "part size mismatch: $part_path"
            return 1
        fi
        actual_sha=$(sha256_file "$part_path")
        if [ "$actual_sha" != "$expected_sha" ]; then
            print_error "part SHA-256 mismatch: $part_path"
            return 1
        fi
    done <"$part_records"

    print_info "Strict SHA-256 verification passed for $expected_part_count parts."
}

concatenate_parts()
{
    selected_part=$1
    output_archive=$2
    parts_manifest=${3-}
    input_prefix=${selected_part%??????}
    : >"$output_archive"

    if [ -n "$parts_manifest" ]; then
        part_records=$WORK_DIR/part-records
        awk -F '\t' '$1 == "part" { print }' "$parts_manifest" >"$part_records"
        joined_count=0
        while IFS="$(printf '\t')" read -r part_tag part_suffix expected_size expected_sha
        do
            [ "$part_tag" = part ] || continue
            cat "$input_prefix$part_suffix" >>"$output_archive"
            joined_count=$((joined_count + 1))
        done <"$part_records"
    else
        joined_count=0
        for archive_part in "$input_prefix"??????
        do
            if [ ! -f "$archive_part" ]; then
                continue
            fi
            suffix=${archive_part#"$input_prefix"}
            case $suffix in
                [a-z][a-z][a-z][a-z][a-z][a-z])
                    cat "$archive_part" >>"$output_archive"
                    joined_count=$((joined_count + 1))
                    ;;
            esac
        done
    fi

    if [ "$joined_count" -eq 0 ]; then
        print_error "no matching archive parts were found"
        return 1
    fi

    print_info "Joined parts: $joined_count"
}

compress_and_split()
{
    source_path=$1

    if [ ! -e "$source_path" ] && [ ! -L "$source_path" ]; then
        print_error "source does not exist: $source_path"
        return 1
    fi

    while [ "$source_path" != / ] && [ "${source_path%/}" != "$source_path" ]
    do
        source_path=${source_path%/}
    done

    if [ "$source_path" = / ]; then
        print_error "archiving the filesystem root directly is refused"
        return 1
    fi

    if ! part_size_bytes=$(size_to_bytes "$PART_SIZE"); then
        print_error "invalid part size: $PART_SIZE"
        print_error "use a positive byte count or a value such as 100M or 2GiB"
        return 2
    fi

    source_dir_input=$(dirname "$source_path")
    source_name=$(basename "$source_path")
    source_dir=$(cd "$source_dir_input" 2>/dev/null && pwd -P) || {
        print_error "cannot access source directory: $source_dir_input"
        return 1
    }

    if [ "$source_name" = . ] || [ "$source_name" = .. ]; then
        canonical_source=$(cd "$source_path" 2>/dev/null && pwd -P) || {
            print_error "cannot resolve source: $source_path"
            return 1
        }
        source_dir=$(dirname "$canonical_source")
        source_name=$(basename "$canonical_source")
    fi

    source_actual=$source_dir/$source_name
    archive_extension=$(engine_extension "$ENGINE")
    archive_file=$source_dir/$source_name.tar.$archive_extension
    output_prefix=$archive_file.part.
    output_manifest=$archive_file.manifest.sha256

    existing_output=0
    for existing_part in "$output_prefix"??????
    do
        if [ -f "$existing_part" ]; then
            existing_output=1
            break
        fi
    done
    if [ "$STRICT_INTEGRITY" -eq 1 ] && [ -e "$output_manifest" ]; then
        existing_output=1
    fi

    if [ "$existing_output" -eq 1 ]; then
        if ! confirm_replace "Archive parts or manifest already exist. Replace them?"; then
            print_info "Operation cancelled."
            return 0
        fi
    fi

    make_work_dir "$source_dir"
    tar_pipe=$WORK_DIR/tar.pipe
    compressed_pipe=$WORK_DIR/compressed.pipe
    temporary_prefix=$WORK_DIR/part.
    temporary_archive=$WORK_DIR/$source_name.tar.$archive_extension
    source_records_before=$WORK_DIR/source-before.records
    source_records_after=$WORK_DIR/source-after.records
    temporary_manifest=$WORK_DIR/manifest.sha256

    mkfifo "$tar_pipe" "$compressed_pipe"

    if [ "$STRICT_INTEGRITY" -eq 1 ]; then
        print_info "Computing strict source SHA-256 inventory..."
        generate_source_records_for_source "$source_actual" "$source_name" \
            "$source_records_before" || return 1
        source_tree_sha=$(sha256_file "$source_records_before")
        print_info "Source tree SHA-256: $source_tree_sha"
    fi

    print_info "Source: $source_actual"
    print_info "Compression engine: $ENGINE"
    print_info "Compression level: $COMPRESSION_LEVEL"
    if engine_supports_threads "$ENGINE"; then
        print_info "Compression threads: $THREADS"
    fi
    print_info "Maximum part size: $PART_SIZE ($part_size_bytes bytes)"

    tar -C "$source_dir" -cf "$tar_pipe" "./$source_name" &
    TAR_PID=$!
    start_compressor "$tar_pipe" "$compressed_pipe"
    split -a "$SUFFIX_LENGTH" -b "$part_size_bytes" \
        "$compressed_pipe" "$temporary_prefix" &
    SPLIT_PID=$!

    pipeline_status=0
    if ! wait "$TAR_PID"; then pipeline_status=1; fi
    TAR_PID=
    if ! wait "$COMPRESS_PID"; then pipeline_status=1; fi
    COMPRESS_PID=
    if ! wait "$SPLIT_PID"; then pipeline_status=1; fi
    SPLIT_PID=

    if [ "$pipeline_status" -ne 0 ]; then
        print_error "archiving, compression, or splitting failed"
        return 1
    fi

    part_count=0
    for temporary_part in "$temporary_prefix"??????
    do
        [ -f "$temporary_part" ] || continue
        suffix=${temporary_part#"$temporary_prefix"}
        case $suffix in
            [a-z][a-z][a-z][a-z][a-z][a-z]) part_count=$((part_count + 1)) ;;
            *) print_error "unexpected split suffix: $suffix"; return 1 ;;
        esac
    done

    if [ "$part_count" -eq 0 ]; then
        print_error "no archive part was created"
        return 1
    fi

    : >"$temporary_archive"
    for temporary_part in "$temporary_prefix"??????
    do
        [ -f "$temporary_part" ] || continue
        cat "$temporary_part" >>"$temporary_archive"
    done

    print_info "Verifying the compressed stream before publishing parts..."
    if ! verify_archive_native "$ENGINE" "$temporary_archive"; then
        print_error "the generated compressed stream failed native verification"
        return 1
    fi

    if [ "$STRICT_INTEGRITY" -eq 1 ]; then
        print_info "Checking that the source did not change during compression..."
        generate_source_records_for_source "$source_actual" "$source_name" \
            "$source_records_after" || return 1
        if ! cmp -s "$source_records_before" "$source_records_after"; then
            print_error "source content changed during compression; no output was published"
            return 1
        fi

        write_integrity_manifest "$temporary_manifest" "$source_records_before" \
            "$source_name" "$temporary_archive" "$temporary_prefix" \
            "$part_count" "$part_size_bytes"
        validate_manifest_structure "$temporary_manifest" || return 1
    fi

    for existing_part in "$output_prefix"??????
    do
        if [ -f "$existing_part" ]; then
            suffix=${existing_part#"$output_prefix"}
            case $suffix in
                [a-z][a-z][a-z][a-z][a-z][a-z]) rm -f "$existing_part" ;;
            esac
        fi
    done
    if [ "$STRICT_INTEGRITY" -eq 1 ]; then
        rm -f "$output_manifest"
    fi

    for temporary_part in "$temporary_prefix"??????
    do
        [ -f "$temporary_part" ] || continue
        suffix=${temporary_part#"$temporary_prefix"}
        mv "$temporary_part" "$output_prefix$suffix"
    done
    if [ "$STRICT_INTEGRITY" -eq 1 ]; then
        mv "$temporary_manifest" "$output_manifest"
    fi

    rm -rf "$WORK_DIR"
    WORK_DIR=

    print_info "Compression and splitting completed."
    print_info "Parts created: $part_count"
    print_info "Output prefix: $output_prefix"
    if [ "$STRICT_INTEGRITY" -eq 1 ]; then
        print_info "Strict-integrity manifest: $output_manifest"
    fi
}

join_parts()
{
    selected_part=$1

    if [ ! -f "$selected_part" ]; then
        print_error "part does not exist: $selected_part"
        return 1
    fi

    if ! detected_engine=$(detect_engine_from_part "$selected_part"); then
        print_error "invalid or unsupported part name"
        print_error "expected format: NAME.tar.EXT.part.aaaaaa"
        return 2
    fi

    ENGINE=$detected_engine
    require_engine "$ENGINE" || return 1
    input_prefix=${selected_part%??????}
    output_file=${input_prefix%.part.}
    output_dir=$(dirname "$output_file")
    output_name=$(basename "$output_file")

    if [ -e "$output_file" ]; then
        if ! confirm_replace "Output archive already exists. Replace it?"; then
            print_info "Operation cancelled."
            LAST_ARCHIVE=$output_file
            return 0
        fi
    fi

    make_work_dir "$output_dir"
    temporary_archive=$WORK_DIR/$output_name
    strict_manifest=

    if [ "$STRICT_INTEGRITY" -eq 1 ]; then
        strict_manifest=$(resolve_manifest "$selected_part" part)
        validate_parts_against_manifest "$selected_part" "$strict_manifest" || return 1
        validate_manifest_archive_identity "$strict_manifest" "$output_file" "$ENGINE" || return 1
    fi

    concatenate_parts "$selected_part" "$temporary_archive" "$strict_manifest" || return 1

    print_info "Detected compression engine: $ENGINE"
    print_info "Verifying the reconstructed compressed stream..."
    if ! verify_archive_native "$ENGINE" "$temporary_archive"; then
        print_error "the reconstructed file failed $ENGINE native verification"
        return 1
    fi

    if [ "$STRICT_INTEGRITY" -eq 1 ]; then
        validate_archive_against_manifest "$temporary_archive" "$ENGINE" \
            "$strict_manifest" || return 1
    fi

    mv -f "$temporary_archive" "$output_file"
    rm -rf "$WORK_DIR"
    WORK_DIR=
    LAST_ARCHIVE=$output_file

    print_info "Archive joined and verified: $output_file"
}

verify_input()
{
    verify_input_path=$1

    if detected_engine=$(detect_engine_from_part "$verify_input_path" 2>/dev/null); then
        if [ ! -f "$verify_input_path" ]; then
            print_error "part does not exist: $verify_input_path"
            return 1
        fi
        ENGINE=$detected_engine
        require_engine "$ENGINE" || return 1
        output_archive=${verify_input_path%??????}
        output_archive=${output_archive%.part.}
        output_dir=$(dirname "$output_archive")
        make_work_dir "$output_dir"
        temporary_archive=$WORK_DIR/$(basename "$output_archive")
        strict_manifest=
        if [ "$STRICT_INTEGRITY" -eq 1 ]; then
            strict_manifest=$(resolve_manifest "$verify_input_path" part)
            validate_parts_against_manifest "$verify_input_path" "$strict_manifest" || return 1
            validate_manifest_archive_identity "$strict_manifest" "$output_archive" "$ENGINE" || return 1
        fi
        concatenate_parts "$verify_input_path" "$temporary_archive" "$strict_manifest" || return 1
        if ! verify_archive_native "$ENGINE" "$temporary_archive"; then
            print_error "reconstructed stream failed native verification"
            return 1
        fi
        if [ "$STRICT_INTEGRITY" -eq 1 ]; then
            validate_archive_against_manifest "$temporary_archive" "$ENGINE" \
                "$strict_manifest" || return 1
        fi
        rm -rf "$WORK_DIR"
        WORK_DIR=
        print_info "Verification completed successfully for the part set."
        return 0
    fi

    if ! detected_engine=$(detect_engine_from_archive "$verify_input_path"); then
        print_error "unsupported archive or part name: $verify_input_path"
        return 2
    fi
    if [ ! -f "$verify_input_path" ]; then
        print_error "archive does not exist: $verify_input_path"
        return 1
    fi

    ENGINE=$detected_engine
    require_engine "$ENGINE" || return 1
    output_dir=$(dirname "$verify_input_path")
    make_work_dir "$output_dir"

    if ! verify_archive_native "$ENGINE" "$verify_input_path"; then
        print_error "archive failed $ENGINE native verification"
        return 1
    fi
    if [ "$STRICT_INTEGRITY" -eq 1 ]; then
        strict_manifest=$(resolve_manifest "$verify_input_path" archive)
        validate_archive_against_manifest "$verify_input_path" "$ENGINE" \
            "$strict_manifest" || return 1
    fi

    rm -rf "$WORK_DIR"
    WORK_DIR=
    print_info "Archive verification completed successfully: $verify_input_path"
}

prepare_extraction_destination()
{
    destination_path=$1

    if [ "$destination_path" = / ] || [ -z "$destination_path" ]; then
        print_error "refusing unsafe extraction destination: $destination_path"
        return 1
    fi

    if [ -e "$destination_path" ] || [ -L "$destination_path" ]; then
        if ! confirm_replace "Extraction destination already exists. Remove and recreate it?"; then
            print_info "Operation cancelled."
            return 1
        fi
        rm -rf "$destination_path"
    fi

    mkdir -p "$destination_path"
}

extract_archive()
{
    extract_input=$1
    extract_archive_path=$extract_input

    if detected_engine=$(detect_engine_from_part "$extract_input" 2>/dev/null); then
        join_parts "$extract_input" || return 1
        extract_archive_path=$LAST_ARCHIVE
    else
        if ! detected_engine=$(detect_engine_from_archive "$extract_input"); then
            print_error "unsupported archive or part name: $extract_input"
            return 2
        fi
        if [ ! -f "$extract_input" ]; then
            print_error "archive does not exist: $extract_input"
            return 1
        fi
        ENGINE=$detected_engine
        require_engine "$ENGINE" || return 1
    fi

    archive_dir=$(dirname "$extract_archive_path")
    archive_base=$(archive_base_without_extension "$extract_archive_path")
    if [ -z "$DESTINATION" ]; then
        extraction_destination=$archive_base.extracted
    else
        extraction_destination=$DESTINATION
    fi

    strict_manifest=
    if [ "$STRICT_INTEGRITY" -eq 1 ]; then
        strict_manifest=$(resolve_manifest "$extract_archive_path" archive)
        make_work_dir "$archive_dir"
        validate_archive_against_manifest "$extract_archive_path" "$ENGINE" \
            "$strict_manifest" || return 1
        rm -rf "$WORK_DIR"
        WORK_DIR=
    fi

    prepare_extraction_destination "$extraction_destination" || return 1
    extraction_parent=$(dirname "$extraction_destination")
    make_work_dir "$extraction_parent"
    tar_pipe=$WORK_DIR/extract.tar.pipe
    mkfifo "$tar_pipe"

    print_info "Extracting with engine $ENGINE to: $extraction_destination"
    start_decompressor "$ENGINE" "$extract_archive_path" "$tar_pipe"
    tar -C "$extraction_destination" -xf "$tar_pipe" &
    EXTRACT_PID=$!

    extraction_status=0
    if ! wait "$COMPRESS_PID"; then extraction_status=1; fi
    COMPRESS_PID=
    if ! wait "$EXTRACT_PID"; then extraction_status=1; fi
    EXTRACT_PID=

    if [ "$extraction_status" -ne 0 ]; then
        print_error "decompression or tar extraction failed"
        return 1
    fi

    if [ "$STRICT_INTEGRITY" -eq 1 ]; then
        extracted_records=$WORK_DIR/extracted-source.records
        expected_records=$WORK_DIR/expected-source.records
        generate_source_records_for_directory_contents "$extraction_destination" \
            "$extracted_records" || return 1
        awk -F '\t' '$1 == "source" { print }' "$strict_manifest" >"$expected_records"
        extracted_sha=$(sha256_file "$extracted_records")
        expected_sha=$(manifest_value source_tree_sha256 "$strict_manifest")

        if [ "$extracted_sha" != "$expected_sha" ] || \
           ! cmp -s "$expected_records" "$extracted_records"; then
            print_error "extracted source tree failed strict SHA-256 validation"
            print_error "expected: $expected_sha"
            print_error "actual:   $extracted_sha"
            return 1
        fi
        print_info "Extracted source tree SHA-256 verified: $extracted_sha"
    fi

    rm -rf "$WORK_DIR"
    WORK_DIR=
    print_info "Extraction completed and verified: $extraction_destination"
}

interactive_mode()
{
    if [ ! -t 0 ]; then
        print_error "no action was specified and standard input is not interactive"
        usage >&2
        return 2
    fi

    printf '%s\n' \
        "tar compression splitter $PROGRAM_VERSION" \
        "1) Compress and split" \
        "2) Join parts" \
        "3) Extract archive or parts" \
        "4) Verify archive or parts" \
        "5) List compression engines" \
        "q) Quit"

    printf 'Select an action: '
    IFS= read -r menu_choice || return 1

    case $menu_choice in
        1|c|C)
            printf 'Source file, directory, or link: '
            IFS= read -r menu_source || return 1
            printf 'Compression engine [zstd]: '
            IFS= read -r menu_engine || return 1
            [ -n "$menu_engine" ] || menu_engine=zstd
            if ! ENGINE=$(normalize_engine "$menu_engine"); then
                print_error "unsupported compression engine: $menu_engine"
                return 2
            fi
            COMPRESSION_LEVEL=$(engine_default_level "$ENGINE")
            printf 'Maximum part size: '
            IFS= read -r PART_SIZE || return 1
            printf 'Enable strict SHA-256 integrity? [y/N] '
            IFS= read -r menu_integrity || return 1
            case $menu_integrity in y|Y|yes|YES|Yes) STRICT_INTEGRITY=1 ;; esac
            require_engine "$ENGINE" || return 1
            [ "$STRICT_INTEGRITY" -eq 0 ] || require_integrity_commands || return 1
            compress_and_split "$menu_source"
            ;;
        2|j|J)
            printf 'Path to any archive part: '
            IFS= read -r menu_part || return 1
            printf 'Require strict SHA-256 manifest? [y/N] '
            IFS= read -r menu_integrity || return 1
            case $menu_integrity in y|Y|yes|YES|Yes) STRICT_INTEGRITY=1 ;; esac
            [ "$STRICT_INTEGRITY" -eq 0 ] || require_integrity_commands || return 1
            join_parts "$menu_part"
            ;;
        3|x|X)
            printf 'Archive or part: '
            IFS= read -r menu_input || return 1
            printf 'Extraction destination [automatic]: '
            IFS= read -r DESTINATION || return 1
            printf 'Require strict SHA-256 manifest? [y/N] '
            IFS= read -r menu_integrity || return 1
            case $menu_integrity in y|Y|yes|YES|Yes) STRICT_INTEGRITY=1 ;; esac
            [ "$STRICT_INTEGRITY" -eq 0 ] || require_integrity_commands || return 1
            extract_archive "$menu_input"
            ;;
        4|v|V)
            printf 'Archive or part: '
            IFS= read -r menu_input || return 1
            printf 'Require strict SHA-256 manifest? [y/N] '
            IFS= read -r menu_integrity || return 1
            case $menu_integrity in y|Y|yes|YES|Yes) STRICT_INTEGRITY=1 ;; esac
            [ "$STRICT_INTEGRITY" -eq 0 ] || require_integrity_commands || return 1
            verify_input "$menu_input"
            ;;
        5|e|E) list_engines ;;
        q|Q) return 0 ;;
        *) print_error "unknown menu selection"; return 2 ;;
    esac
}

main()
{
    if [ "$#" -eq 0 ]; then
        require_base_commands
        interactive_mode
        return
    fi

    case ${1-} in
        --help) usage; return 0 ;;
        --engines) list_engines; return 0 ;;
    esac

    OPTIND=1
    while getopts ':cjxve:s:l:T:im:d:fEh' option
    do
        case $option in
            c|j|x|v)
                if [ -n "$ACTION" ]; then
                    print_error "only one action may be specified"
                    usage >&2
                    return 2
                fi
                case $option in
                    c) ACTION=compress ;;
                    j) ACTION=join ;;
                    x) ACTION=extract ;;
                    v) ACTION=verify ;;
                esac
                ;;
            e) ENGINE=$OPTARG; ENGINE_SET=1 ;;
            s) PART_SIZE=$OPTARG ;;
            l) COMPRESSION_LEVEL=$OPTARG ;;
            T) THREADS=$OPTARG; THREADS_SET=1 ;;
            i) STRICT_INTEGRITY=1 ;;
            m) MANIFEST_FILE=$OPTARG ;;
            d) DESTINATION=$OPTARG ;;
            f) FORCE=1 ;;
            E) list_engines; return 0 ;;
            h) usage; return 0 ;;
            :) print_error "option -$OPTARG requires an argument"; usage >&2; return 2 ;;
            \?) print_error "unknown option: -$OPTARG"; usage >&2; return 2 ;;
        esac
    done
    shift $((OPTIND - 1))

    if [ -z "$ACTION" ]; then
        print_error "one action is required: -c, -j, -x, or -v"
        usage >&2
        return 2
    fi

    require_base_commands
    if [ "$STRICT_INTEGRITY" -eq 1 ]; then
        require_integrity_commands
    fi

    case $ACTION in
        compress)
            if ! ENGINE=$(normalize_engine "$ENGINE"); then
                print_error "unsupported compression engine"
                list_engines >&2
                return 2
            fi
            [ -z "$COMPRESSION_LEVEL" ] && COMPRESSION_LEVEL=$(engine_default_level "$ENGINE")
            if ! validate_engine_level "$ENGINE" "$COMPRESSION_LEVEL"; then
                print_error "invalid compression level for engine $ENGINE: $COMPRESSION_LEVEL"
                return 2
            fi
            if ! validate_nonnegative_integer "$THREADS"; then
                print_error "thread count must be a non-negative integer"
                return 2
            fi
            if [ "$THREADS_SET" -eq 1 ] && ! engine_supports_threads "$ENGINE"; then
                print_error "option -T is not supported by engine $ENGINE"
                return 2
            fi
            [ -z "$PART_SIZE" ] && { print_error "option -s SIZE is required with -c"; return 2; }
            [ -z "$MANIFEST_FILE" ] || { print_error "option -m is not valid with -c"; return 2; }
            [ -z "$DESTINATION" ] || { print_error "option -d is not valid with -c"; return 2; }
            [ "$#" -eq 1 ] || { print_error "compression requires exactly one SOURCE operand"; return 2; }
            require_engine "$ENGINE" || return 1
            compress_and_split "$1"
            ;;
        join)
            [ "$ENGINE_SET" -eq 0 ] || { print_error "option -e is not valid with -j"; return 2; }
            [ -z "$PART_SIZE" ] || { print_error "option -s is not valid with -j"; return 2; }
            [ -z "$COMPRESSION_LEVEL" ] || { print_error "option -l is not valid with -j"; return 2; }
            [ "$THREADS_SET" -eq 0 ] || { print_error "option -T is not valid with -j"; return 2; }
            [ -z "$DESTINATION" ] || { print_error "option -d is not valid with -j"; return 2; }
            [ "$#" -eq 1 ] || { print_error "joining requires exactly one PART operand"; return 2; }
            [ -z "$MANIFEST_FILE" ] || [ "$STRICT_INTEGRITY" -eq 1 ] || {
                print_error "option -m requires -i"; return 2;
            }
            join_parts "$1"
            ;;
        extract)
            [ "$ENGINE_SET" -eq 0 ] || { print_error "option -e is not valid with -x"; return 2; }
            [ -z "$PART_SIZE" ] || { print_error "option -s is not valid with -x"; return 2; }
            [ -z "$COMPRESSION_LEVEL" ] || { print_error "option -l is not valid with -x"; return 2; }
            [ "$THREADS_SET" -eq 0 ] || { print_error "option -T is not valid with -x"; return 2; }
            [ "$#" -eq 1 ] || { print_error "extraction requires exactly one INPUT operand"; return 2; }
            [ -z "$MANIFEST_FILE" ] || [ "$STRICT_INTEGRITY" -eq 1 ] || {
                print_error "option -m requires -i"; return 2;
            }
            extract_archive "$1"
            ;;
        verify)
            [ "$ENGINE_SET" -eq 0 ] || { print_error "option -e is not valid with -v"; return 2; }
            [ -z "$PART_SIZE" ] || { print_error "option -s is not valid with -v"; return 2; }
            [ -z "$COMPRESSION_LEVEL" ] || { print_error "option -l is not valid with -v"; return 2; }
            [ "$THREADS_SET" -eq 0 ] || { print_error "option -T is not valid with -v"; return 2; }
            [ -z "$DESTINATION" ] || { print_error "option -d is not valid with -v"; return 2; }
            [ "$#" -eq 1 ] || { print_error "verification requires exactly one INPUT operand"; return 2; }
            [ -z "$MANIFEST_FILE" ] || [ "$STRICT_INTEGRITY" -eq 1 ] || {
                print_error "option -m requires -i"; return 2;
            }
            verify_input "$1"
            ;;
    esac
}

main "$@"
