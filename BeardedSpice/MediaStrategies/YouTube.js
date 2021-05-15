//
//  YouTube.plist
//  BeardedSpice
//
//  Created by Jose Falcon on 12/15/13.
//  Updated by Alin Panaitiu on 3/2/18.
//  Updated by Vladislav Gapurov on 07/28/18
//  Updated by Andreas Willi on 02/24/19
//  Copyright (c) 2021 GPL v3 http://www.gnu.org/licenses/gpl.html
//

BSStrategy = {
  version: 5,
  displayName: "YouTube",
  homepage: "https://www.youtube.com/",
  accepts: {
    method: "predicateOnTab",
    format: "%K LIKE[c] '*youtube.com/watch*' && !%@ LIKE[c] '*music.youtube.com*'",
    args: ["URL", "URL"]
  },
  isPlaying: function () { return !document.querySelector('#movie_player video').paused; },
  toggle: function () { document.querySelector('#movie_player .ytp-play-button').click(); },
  previous: function () { document.querySelector('#movie_player').previousVideo(); },
  next: function () { document.querySelector('#movie_player').nextVideo(); },
  pause: function () { document.querySelector('#movie_player').pauseVideo(); },
  favorite: function () { document.querySelector('ytd-toggle-button-renderer').click(); },
  trackInfo: function () {
    function pad(number) {
      if (number < 10) {
        return `0${number}`;
      } else {
        return number.toString();
      }
    };

    function secondsToTimeString(seconds) {
      let hours = Math.floor(seconds / 3600);
      let minutes = Math.floor(seconds / 60);
      let seconds = Math.floor(seconds % 60);

      if (hours > 0) {
        return `${pad(hours)}:${pad(minutes)}:${pad(seconds)}`;
      } else {
        return `${pad(minutes)}:${pad(seconds)}`;
      }
    };

    let playerManager = document.querySelector('yt-player-manager');
    let player = playerManager.player_;
    let videoData = player.getVideoData();

    let progress = player.getProgressState();
    let played = secondsToTimeString(progress.current);
    let duration = secondsToTimeString(progress.duration);

    return {
      'image': `https://i.ytimg.com/vi/${videoData.video_id}/hqdefault.jpg`,
      'track': videoData.title,
      'artist': videoData.author,
      'progress': `${played} of ${duration}`,
      'favorited': document.querySelector('ytd-toggle-button-renderer').data.isToggled
    };
  }
}
