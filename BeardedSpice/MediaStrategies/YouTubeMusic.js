//
//  YouTubeMusic.plist
//  BeardedSpice
//
//  Created by Vladislav Gapurov on 07/28/18
//  Copyright (c) 2021 GPL v3 http://www.gnu.org/licenses/gpl.html
//

BSStrategy = {
  version: 2,
  displayName: "YouTube Music",
  homepage: "https://music.youtube.com/",
  accepts: {
    method: "predicateOnTab",
    format: "%K LIKE[c] '*music.youtube.com/*'",
    args: ["URL"],
  },
  isPlaying: function() { return !document.querySelector('#movie_player video').paused; },
  toggle: function() { document.querySelector('.ytmusic-player-bar.play-pause-button').click(); },
  previous: function() { document.querySelector('.ytmusic-player-bar.previous-button').click(); },
  next: function() { document.querySelector('.ytmusic-player-bar.next-button').click(); },
  pause: function() {
    if(!document.querySelector('#movie_player video').paused) {
      document.querySelector('.ytmusic-player-bar.play-pause-button').click();
    }
  },
  favorite: function() {
    document.querySelector('ytmusic-like-button-renderer .ytmusic-like-button-renderer.like').click()
  },
  trackInfo: function() {
    let timeInfo = document.querySelector('.ytmusic-player-bar.time-info').innerHTML.split('/');
    let thumb = document.querySelector('.ytmusic-player-bar img');
    let title = document.querySelector('.ytmusic-player-bar.title');
    let byline = document.querySelector('.byline.ytmusic-player-bar');
    let like = document.querySelector('ytmusic-like-button-renderer');

    return {
      'image': thumb.src,
      'track': title.text.runs[0].text,
      'artist': Array.from(byline.children)
        .reduce((acc, curr, i) => i === 0 ? curr.text : `${acc}, ${curr.text}`, '' ),
      'progress': `${timeInfo[0].trim()} of ${timeInfo[1].trim()}`,
      'favorited': like.getAttribute('like-status') === 'LIKE',
    };
  },
};
