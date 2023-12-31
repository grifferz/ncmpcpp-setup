# ncmpcpp-setup
Supporting files and instructions for my ncmpcpp setup.

On my desktop this results in something like this:

![Screenshot of ncmpcpp running in a kitty terminal, with album cover art and a
track change notification](screenshot.png)

There's a [blog
article](https://strugglers.net/~andy/blog/2023/12/26/ncmpcpp-a-modernish-text-based-music-setup-on-linux)
with more discussion of these files and their use, but basically:

- Put the following in **$HOME/.ncmpcpp/**:
  - [album_cover_poller.sh](album_cover_poller)
  - [default_cover.jpg](default_cover.jpg)
  - [track_change.sh](track_change.sh)
  - [viz.conf](viz.conf)
- Put [ncmpcpp.session](ncmpcpp.session) in **$HOME/.config/kitty/**.
- Put [mpd-mpris.service](mpd-mpris.service) in **$HOME/.config/systemd/user/**.
- Add ```execute_on_song_change =
"~/.ncmpcpp/track_change.sh -m /path/to/your/music/dir"``` to your
**$HOME/.ncmpcpp/config**. The **/path/to/your/music/dir** is the same as what
is set in your MPD configuration for its library.
