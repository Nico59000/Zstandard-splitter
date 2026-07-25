#!/bin/sh

# zstd-splitter.sh
# Create a tar archive, compress it with a selectable stream compressor,
# split it into parts, or join those parts back into a verified archive.
#
# Zstandard remains the default engine for backward compatibility.
# The command-line interface follows POSIX utility conventions: short options,
# getopts parsing, options before operands, and -- as the end-of-options marker.
# The script itself is written for POSIX /bin/sh.

set -eu
LC_ALL=C
export LC_ALL

PROGRAM_NAME=${0##*/}
SUFFIX_LENGTH=6
ACTION=
PART_SIZE=
ENGINE=zstd
ENGINE_SET=0
COMPRESSION_LEVEL=
THREADS=0
THREADS_SET=0
FORCE=0
WORK_DIR=
TAR_PID=
COMPRESS_PID=
SPLIT_PID=

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
  $PROGRAM_NAME -c -s SIZE [-e ENGINE] [-l LEVEL] [-T THREADS] [-f] SOURCE
  $PROGRAM_NAME -j [-f] PART
  $PROGRAM_NAME -E
  $PROGRAM_NAME -h
  $PROGRAM_NAME

Actions:
  -c            Create a tar archive, compress it, and split it.
  -j            Join archive parts and verify the reconstructed stream.
  -E            List supported compression engines.

Options:
  -e ENGINE     Compression engine used with -c. Default: zstd.
                Accepted engines: zstd, gzip, bzip2, xz, lzma,
                lzip, lzop, and lz4.
  -s SIZE       Maximum size of each part. Required with -c.
                SIZE may be a positive byte count or use K, M, G, T, or P,
                optionally followed by B or iB. Units are powers of 1024.
  -l LEVEL      Compression level. The accepted range depends on ENGINE.
                When omitted, the engine-specific default is used.
  -T THREADS    Worker threads for zstd, xz, or lzma.
                Default: 0, meaning automatic selection by the engine.
  -f            Replace existing output without asking for confirmation.
  -h            Display this help text and exit.
  --            End option processing.

Operands:
  SOURCE        File or directory to archive.
  PART          Any part named like NAME.tar.EXT.part.aaaaaa.

Examples:
  $PROGRAM_NAME -c -s 500M "/path/My directory"
  $PROGRAM_NAME -c -e gzip -s 100M -l 9 disk-image.raw
  $PROGRAM_NAME -c -e xz -s 2GiB -l 6 -T 0 source-directory
  $PROGRAM_NAME -j "/path/My directory.tar.gz.part.aaaaac"
  $PROGRAM_NAME -j -f archive.tar.xz.part.aaaaaa
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

    if [ -n "$TAR_PID" ]; then
        kill "$TAR_PID" 2>/dev/null || :
    fi
    if [ -n "$COMPRESS_PID" ]; then
        kill "$COMPRESS_PID" 2>/dev/null || :
    fi
    if [ -n "$SPLIT_PID" ]; then
        kill "$SPLIT_PID" 2>/dev/null || :
    fi

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
    for required_command in tar split cat mkdir rm mv dirname basename mkfifo awk
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

start_compressor()
{
    compressor_input=$1
    compressor_output=$2

    case $ENGINE in
        zstd)
            zstd -q -T"$THREADS" -"$COMPRESSION_LEVEL" -c \
                <"$compressor_input" >"$compressor_output" &
            ;;
        gzip)
            gzip -c -"$COMPRESSION_LEVEL" \
                <"$compressor_input" >"$compressor_output" &
            ;;
        bzip2)
            bzip2 -c -"$COMPRESSION_LEVEL" \
                <"$compressor_input" >"$compressor_output" &
            ;;
        xz)
            xz -c -"$COMPRESSION_LEVEL" -T"$THREADS" \
                <"$compressor_input" >"$compressor_output" &
            ;;
        lzma)
            xz --format=lzma -c -"$COMPRESSION_LEVEL" -T"$THREADS" \
                <"$compressor_input" >"$compressor_output" &
            ;;
        lzip)
            lzip -q -c -"$COMPRESSION_LEVEL" \
                <"$compressor_input" >"$compressor_output" &
            ;;
        lzop)
            lzop -q -c -"$COMPRESSION_LEVEL" \
                <"$compressor_input" >"$compressor_output" &
            ;;
        lz4)
            lz4 -q -z -c -"$COMPRESSION_LEVEL" \
                <"$compressor_input" >"$compressor_output" &
            ;;
        *)
            print_error "unsupported compression engine: $ENGINE"
            return 1
            ;;
    esac

    COMPRESS_PID=$!
}

verify_archive()
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

compress_and_split()
{
    source_path=$1

    if [ ! -e "$source_path" ]; then
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

    archive_extension=$(engine_extension "$ENGINE")
    source_dir=$(dirname "$source_path")
    source_name=$(basename "$source_path")
    output_prefix=$source_dir/$source_name.tar.$archive_extension.part.

    existing_parts=0
    for existing_part in "$output_prefix"??????
    do
        if [ -f "$existing_part" ]; then
            case ${existing_part#"$output_prefix"} in
                [a-z][a-z][a-z][a-z][a-z][a-z])
                    existing_parts=1
                    break
                    ;;
            esac
        fi
    done

    if [ "$existing_parts" -eq 1 ]; then
        if ! confirm_replace "Archive parts already exist. Replace them?"; then
            print_info "Operation cancelled."
            return 0
        fi
    fi

    make_work_dir "$source_dir"
    tar_pipe=$WORK_DIR/tar.pipe
    compressed_pipe=$WORK_DIR/compressed.pipe
    temporary_prefix=$WORK_DIR/part.

    mkfifo "$tar_pipe" "$compressed_pipe"

    print_info "Source: $source_path"
    print_info "Compression engine: $ENGINE"
    print_info "Compression level: $COMPRESSION_LEVEL"
    if engine_supports_threads "$ENGINE"; then
        print_info "Compression threads: $THREADS"
    fi
    print_info "Maximum part size: $PART_SIZE ($part_size_bytes bytes)"

    tar -C "$source_dir" -cf "$tar_pipe" "$source_name" &
    TAR_PID=$!

    start_compressor "$tar_pipe" "$compressed_pipe"

    split -a "$SUFFIX_LENGTH" -b "$part_size_bytes" \
        "$compressed_pipe" "$temporary_prefix" &
    SPLIT_PID=$!

    pipeline_status=0
    if ! wait "$TAR_PID"; then
        pipeline_status=1
    fi
    TAR_PID=

    if ! wait "$COMPRESS_PID"; then
        pipeline_status=1
    fi
    COMPRESS_PID=

    if ! wait "$SPLIT_PID"; then
        pipeline_status=1
    fi
    SPLIT_PID=

    if [ "$pipeline_status" -ne 0 ]; then
        print_error "archiving, compression, or splitting failed"
        return 1
    fi

    part_count=0
    for temporary_part in "$temporary_prefix"??????
    do
        if [ ! -f "$temporary_part" ]; then
            continue
        fi

        suffix=${temporary_part#"$temporary_prefix"}
        case $suffix in
            [a-z][a-z][a-z][a-z][a-z][a-z])
                part_count=$((part_count + 1))
                ;;
            *)
                print_error "unexpected split suffix: $suffix"
                return 1
                ;;
        esac
    done

    if [ "$part_count" -eq 0 ]; then
        print_error "no archive part was created"
        return 1
    fi

    temporary_archive=$WORK_DIR/archive.tar.$archive_extension
    : >"$temporary_archive"
    for temporary_part in "$temporary_prefix"??????
    do
        if [ -f "$temporary_part" ]; then
            cat "$temporary_part" >>"$temporary_archive"
        fi
    done

    print_info "Verifying the compressed stream before publishing parts..."
    if ! verify_archive "$ENGINE" "$temporary_archive"; then
        print_error "the generated compressed stream failed integrity verification"
        return 1
    fi
    rm -f "$temporary_archive"

    if [ "$existing_parts" -eq 1 ]; then
        for existing_part in "$output_prefix"??????
        do
            if [ -f "$existing_part" ]; then
                suffix=${existing_part#"$output_prefix"}
                case $suffix in
                    [a-z][a-z][a-z][a-z][a-z][a-z]) rm -f "$existing_part" ;;
                esac
            fi
        done
    fi

    for temporary_part in "$temporary_prefix"??????
    do
        if [ -f "$temporary_part" ]; then
            suffix=${temporary_part#"$temporary_prefix"}
            mv "$temporary_part" "$output_prefix$suffix"
        fi
    done

    rm -rf "$WORK_DIR"
    WORK_DIR=

    print_info "Compression and splitting completed."
    print_info "Parts created: $part_count"
    print_info "Output prefix: $output_prefix"
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
            return 0
        fi
    fi

    make_work_dir "$output_dir"
    temporary_archive=$WORK_DIR/$output_name
    : >"$temporary_archive"

    part_count=0
    for archive_part in "$input_prefix"??????
    do
        if [ ! -f "$archive_part" ]; then
            continue
        fi

        suffix=${archive_part#"$input_prefix"}
        case $suffix in
            [a-z][a-z][a-z][a-z][a-z][a-z])
                cat "$archive_part" >>"$temporary_archive"
                part_count=$((part_count + 1))
                ;;
        esac
    done

    if [ "$part_count" -eq 0 ]; then
        print_error "no matching archive parts were found"
        return 1
    fi

    print_info "Detected compression engine: $ENGINE"
    print_info "Joined parts: $part_count"
    print_info "Verifying the reconstructed compressed stream..."

    if ! verify_archive "$ENGINE" "$temporary_archive"; then
        print_error "the reconstructed file failed $ENGINE integrity verification"
        return 1
    fi

    mv -f "$temporary_archive" "$output_file"
    rm -rf "$WORK_DIR"
    WORK_DIR=

    print_info "Archive joined and verified: $output_file"
}

interactive_mode()
{
    if [ ! -t 0 ]; then
        print_error "no action was specified and standard input is not interactive"
        usage >&2
        return 2
    fi

    printf '%s\n' \
        "tar compression splitter" \
        "1) Compress and split" \
        "2) Join parts" \
        "3) List compression engines" \
        "q) Quit"

    printf 'Select an action: '
    IFS= read -r menu_choice || return 1

    case $menu_choice in
        1|c|C)
            printf 'Source file or directory: '
            IFS= read -r menu_source || return 1
            printf 'Compression engine [zstd]: '
            IFS= read -r menu_engine || return 1
            if [ -z "$menu_engine" ]; then
                menu_engine=zstd
            fi
            if ! ENGINE=$(normalize_engine "$menu_engine"); then
                print_error "unsupported compression engine: $menu_engine"
                return 2
            fi
            COMPRESSION_LEVEL=$(engine_default_level "$ENGINE")
            printf 'Maximum part size: '
            IFS= read -r menu_size || return 1
            PART_SIZE=$menu_size
            require_engine "$ENGINE" || return 1
            compress_and_split "$menu_source"
            ;;
        2|j|J)
            printf 'Path to any archive part: '
            IFS= read -r menu_part || return 1
            join_parts "$menu_part"
            ;;
        3|e|E)
            list_engines
            ;;
        q|Q)
            return 0
            ;;
        *)
            print_error "unknown menu selection"
            return 2
            ;;
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
        --help)
            usage
            return 0
            ;;
        --engines)
            list_engines
            return 0
            ;;
    esac

    OPTIND=1
    while getopts ':cje:s:l:T:fEh' option
    do
        case $option in
            c)
                if [ -n "$ACTION" ]; then
                    print_error "only one action may be specified"
                    usage >&2
                    return 2
                fi
                ACTION=compress
                ;;
            j)
                if [ -n "$ACTION" ]; then
                    print_error "only one action may be specified"
                    usage >&2
                    return 2
                fi
                ACTION=join
                ;;
            e)
                ENGINE=$OPTARG
                ENGINE_SET=1
                ;;
            s)
                PART_SIZE=$OPTARG
                ;;
            l)
                COMPRESSION_LEVEL=$OPTARG
                ;;
            T)
                THREADS=$OPTARG
                THREADS_SET=1
                ;;
            f)
                FORCE=1
                ;;
            E)
                list_engines
                return 0
                ;;
            h)
                usage
                return 0
                ;;
            :)
                print_error "option -$OPTARG requires an argument"
                usage >&2
                return 2
                ;;
            \?)
                print_error "unknown option: -$OPTARG"
                usage >&2
                return 2
                ;;
        esac
    done
    shift $((OPTIND - 1))

    if [ -z "$ACTION" ]; then
        print_error "one action is required: -c or -j"
        usage >&2
        return 2
    fi

    require_base_commands

    case $ACTION in
        compress)
            if ! ENGINE=$(normalize_engine "$ENGINE"); then
                print_error "unsupported compression engine"
                list_engines >&2
                return 2
            fi

            if [ -z "$COMPRESSION_LEVEL" ]; then
                COMPRESSION_LEVEL=$(engine_default_level "$ENGINE")
            fi

            if ! validate_engine_level "$ENGINE" "$COMPRESSION_LEVEL"; then
                print_error "invalid compression level for engine $ENGINE: $COMPRESSION_LEVEL"
                list_engines >&2
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

            if [ -z "$PART_SIZE" ]; then
                print_error "option -s SIZE is required with -c"
                usage >&2
                return 2
            fi

            if [ "$#" -ne 1 ]; then
                print_error "compression requires exactly one SOURCE operand"
                usage >&2
                return 2
            fi

            require_engine "$ENGINE" || return 1
            compress_and_split "$1"
            ;;
        join)
            if [ "$ENGINE_SET" -eq 1 ]; then
                print_error "option -e is not valid with -j; the engine is detected from PART"
                return 2
            fi
            if [ -n "$PART_SIZE" ]; then
                print_error "option -s is not valid with -j"
                return 2
            fi
            if [ -n "$COMPRESSION_LEVEL" ]; then
                print_error "option -l is not valid with -j"
                return 2
            fi
            if [ "$THREADS_SET" -eq 1 ]; then
                print_error "option -T is not valid with -j"
                return 2
            fi
            if [ "$#" -ne 1 ]; then
                print_error "joining requires exactly one PART operand"
                usage >&2
                return 2
            fi
            join_parts "$1"
            ;;
    esac
}

main "$@"
