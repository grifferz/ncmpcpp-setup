#!/bin/bash

# $HOME/.ncmpcpp/track_change.sh

# © Andy Smith <andy@strugglers.net>
# SPDX-License-Identifier: 0BSD

set -eu

### Some things user might want to change.

# This is the path to the music library as known by mpd.
music_base="/path/to/your/music"

# File name that each album's art is stored under.
candidate_name="cover.jpg"

# Directory to place the current track's cover in. Can be some temporary or
# cache directory - we'll create it if it doesn't exist already.
# This will typically be something like /run/user/1000/ncmpcpp
cover_dir="$XDG_RUNTIME_DIR/ncmpcpp"

# Where all your ncmpcpp files live, though we only use this as part of the
# "default" cover image path.
ncmpcpp_home="$HOME/.ncmpcpp"

# Path to an image to use when we don't have a better album cover image.
default_cover="$ncmpcpp_home/default_cover.jpg"

# This path we'll copy the correct cover image to.
ncmpcpp_cover="$cover_dir/current_cover.jpg"

# How many milliseconds to keep the desktop notification visible for. A lot of
# notiifcation daemons don't support this, e.g. GNOME just ignores it, but
# Dunst and Wired do. On GNOME you can use this extension to change the timeout
# for all notification popups:
#     https://extensions.gnome.org/extension/3795/notification-timeout/
notification_timeout=10000

### No user-serviceable parts below here.

error() {
    logger -t "$(basename "$0")" "${*}"
    printf "%s\\n" "%{*}" 1>&2
}

warning() {
    logger -t "$(basename "$0")" "${*}"
}

use_album_cover() {
    # Always copy the default cover, because otherwise the inotify in the
    # poller won't trigger and album info for things with no cover will never
    # be displayed.
    # Otherwise only bother if the files are actually different (think -
    # playing consecutive tracks of same album).
    if [ "$1" = "$default_cover" ] || ! cmp --silent "$1" "$ncmpcpp_cover"; then
        cp "$1" "$ncmpcpp_cover"
    fi
}

do_desktop_notification() {
    # ${meta[0]} = file
    # ${meta[1]} = artist
    # ${meta[2]} = title
    # ${meta[3]} = albumartist
    # ${meta[4]} = album
    # ${meta[5]} = date
    # ${meta[6]} = originaldate
    local -n meta="$1"
    local cover_art="$2"

    local artist
    local title
    local albumartist
    local year
    local album

    artist="${meta[1]}"
    title="${meta[2]}"

    # If we don't have an album artist then we'll just assume the track artist.
    if [ -n "${meta[3]}" ]; then
        albumartist="${meta[3]}"
    else
        albumartist="$artist"
    fi

    # If we know the original date, use that, else the date, else nothing.
    if [ "${meta[6]+x}" ]; then
        year="${meta[6]}"
    elif [ "${meta[5]+x}" ]; then
        year="${meta[5]}"
    fi

    if [ -z "${meta[4]+x}" ]; then
        album="Unknown Album"
    else
        album="${meta[4]}"
    fi

    # Add the year on the end of the album if we have it.
    if [ -n "$year" ]; then
        album="$album • $year"
    fi

    # libnotify as supported by most desktops. e.g. in Debian it's from
    # libnotify-bin package. Your typical GNOME desktop notification.
    #
    # Set normal priority as otherwise GNOME hides it away in the notification
    # tray.
    #
    # Set transient so it doesn't stack them up inside the tray.
    #
    # Transient hint not necessary on GNOME but might be elsewhere.
    #
    # image-path hint uses the album cover as the notification icon. This seems
    # quite unreliable on GNOME, like it caches an old one for ages, but it
    # seems to do that by file path so we can bust the cache by sending the
    # path to the original file (not the one that the poller script is
    # watching).
    notify-send \
        --app-name MPD \
        --urgency normal \
        --expire-time="$notification_timeout" \
        --transient \
        --hint="int:transient:1" \
        --hint="string:image-path:$cover_art" \
        "$artist • $title" \
        "$albumartist • $album"
}

# Get all the metadata from mpd.
# I sure hope none of it ever contains a tab…
while IFS= read -r mpc_line; do
    # This grossness needed to handle the case where a field might be
    # empty. If we did the usual IFS=$'\t' then it would skip over the
    # empty field, so we have to use mapfile to explode it into an array
    # instead.
    mapfile -td $'\t' mpc < <(printf %s "$mpc_line")
done < <(mpc \
    -f '%file%\t%artist%\t%title%\t%albumartist%\t%album%\t%date%\t%originaldate%' \
    current)

track_file="${mpc[0]}"
full_track_file="$music_base/$track_file"

# Sanity checks - can't work out an album cover without knowing an existing
# directory path.
if [ ! -r "$full_track_file" ]; then
    error "mpd said that file '$full_track_file' is currently playing but it
doesn't seem to exist"
    use_album_cover "$default_cover"
else
    if [ ! -d "$cover_dir" ]; then
        mkdir -p "$cover_dir"
    fi

    # The $track_file can be in these various formats:
    #
    # a) Artist/Album/Track.mp3
    # b) Various Artists/Album/Track.mp3
    # c) Artist/Track.mp3
    #
    # Case (c) is not handled yet as this is for album art and we don't know
    # the album. In future we might try to extract cover art from the file, or
    # look for it in a separate file once we know where to look on a per-file
    # basis.

    # This removes everything that's NOT a "/" out of the track file path.
    only_slashes="${track_file//[^\/]}"
    # So we can count them.
    slash_count="${#only_slashes}"

    case "$slash_count" in
        "2")
            containing_dir="$(dirname "$full_track_file")"

            if [ -r "$containing_dir/$candidate_name" ]; then
                chosen_cover="$containing_dir/$candidate_name"
                use_album_cover "$chosen_cover"
            else
                chosen_cover="$default_cover"
                use_album_cover "$chosen_cover"
            fi
            ;;
        "1")
            warning "non-album track '$track_file' not handled yet"
            chosen_cover="$default_cover"
            use_album_cover "$chosen_cover"
            ;;
        *)
            warning "Don't know how to handle track path '$full_track_file'"
            chosen_cover="$default_cover"
            use_album_cover "$chosen_cover"
            ;;
    esac
fi

# ${mpc[0]} = file
# ${mpc[1]} = artist
# ${mpc[2]} = title
# ${mpc[3]} = albumartist
# ${mpc[4]} = album
# ${mpc[5]} = date
# ${mpc[6]} = originaldate
#
# We need at least an artist and a title to do a desktop notification.
if [ -z "${mpc[1]}" ] || [ -z "${mpc[2]}" ]; then
    warning "Current track '$full_track_file' didn't give us an artist and title,
so no desktop notification"
else
    do_desktop_notification mpc "$chosen_cover"
fi
