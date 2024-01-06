#!/usr/bin/env bash

# $HOME/.ncmpcpp/album_cover_poller.sh

# © Andy Smith <andy@strugglers.net>
# SPDX-License-Identifier: 0BSD

ncmpcpp_home="$HOME/.ncmpcpp"
default_cover="$ncmpcpp_home/default_cover.jpg"
cover_dir="$XDG_RUNTIME_DIR/ncmpcpp"
ncmpcpp_cover="$cover_dir/current_cover.jpg"

green="$(tput setaf 2)"
normal="$(tput sgr0)"

display_centered_at_row() {
    local termwidth
    termwidth="$(tput cols)"
    local input="$1"
    local row="$2"

    local cleaned_input
    local input_len

    # This horrible sed that I got from somewhere strips out all ANSI escape
    # sequences from the input, because otherwise we'll miscalculate how long
    # it is. We still will get it wrong for multibyte Unicode stuff but meh…
    cleaned_input=$(printf "%s" "$input" |
        sed 's/\x1B[@A-Z\\\]^_]\|\x1B\[[0-9:;<=>?]*[-!"#$%&'"'"'()*+,.\/]*[][\\@A-Z^_`a-z{|}~]//g')
    # Calculate length of string. Would "wc -m" do better at handling non-ASCII?
    input_len="${#cleaned_input}"

    if ((input_len >= termwidth)); then
        # String is as big as or bigger than our terminal, so it's going to
        # wrap. Let's make it wrap nicely.
        newrow="$row"
        while read -r line; do
            display_centered_at_row "$line" "$newrow"
            (( newrow++ ))
        done < <(printf "%s" "$input" | fmt -w "$termwidth")
    else
        local start_pos
        start_pos="$(( (termwidth - input_len) / 2))"
        printf '\e[%u;%uH' "$row" "$start_pos"
        printf "%s\n" "$input"
    fi
}

show_cover() {
    clear
    # Get all the metadata from mpd.
    mpc \
        -f '%artist%\t%albumartist%\t%album%\t%date%\t%originaldate%' \
        current | \
    while IFS= read -r mpc_line; do
        # This grossness needed to handle the case where a field might be
        # empty. If we did the usual IFS=$'\t' then it would skip over the
        # empty field, so we have to use mapfile to explode it into an array
        # instead.
        mapfile -td $'\t' mpc < <(printf %s "$mpc_line")
        if [[ -z "${mpc[1]}" ]]; then
            current_artist="${mpc[0]}"
        else
            current_artist="${mpc[1]}"
        fi;

        if [[ -z "${mpc[4]}" && -z "${mpc[3]}" ]]; then
            # No date known at all.
            current_year="unknown year"
        elif [[ -z "${mpc[4]}" ]]; then
            current_year="${mpc[3]}"
        else
            current_year="${mpc[4]}"
        fi

        if [[ -z "${mpc[2]}" ]]; then
            current_album="Unknown Album"
        else
            current_album="${mpc[2]}"
        fi

        display_centered_at_row "${green}${current_artist}${normal}" 1
        display_centered_at_row \
            "'${green}${current_album}${normal}' (${green}${current_year}${normal})" 2
        printf "\n"
    done
    timg --center "$ncmpcpp_cover"
}

if [[ ! -d "$cover_dir" ]]; then
    mkdir -vp "$cover_dir"
    cp "$default_cover" "$ncmpcpp_cover"
fi

if [[ ! -f "$ncmpcpp_cover" ]]; then
    cp "$default_cover" "$ncmpcpp_cover"
fi

# Initially show whatever cover file is already there, which will either be
# what we last played or the default cover.
show_cover

# And then wait on an inotify event indicating that something has closed our
# cover image file after writing to it.
while inotifywait \
    --syslog --quiet --quiet --event close_write "$ncmpcpp_cover"; do
    show_cover
done
