//
//  Spotify.plist
//  BeardedSpice
//
//  Created by Jose Falcon on 12/19/13.
//  Modified by Bonapara on 14/09/2022
//  Copyright (c) 2022 GPL v3 http://www.gnu.org/licenses/gpl.html
//
BSStrategy = {
  version:4,
  displayName:"Spotify",
  homepage: 'https://spotify.com/',
  accepts: {
    method: "predicateOnTab",
    format:"%K LIKE[c] '*open.spotify.com*'",
    args: ["URL"]
  },
  isPlaying: function() {
    return !!(document.querySelector('div.player-controls__buttons button[data-testid="control-button-playpause"] svg>path[d*="zm"]'));
  },
  toggle: function () {
    document.querySelector('div.player-controls__buttons button[data-testid="control-button-playpause"]').click();
  },
  next: function () {
    document.querySelector('div.player-controls__buttons button[data-testid="control-button-skip-forward"]').click();
  },
  favorite: function () {
    document.querySelector('div.control-button.control-button-heart > button').click()    
  },
  previous: function () {
    document.querySelector('div.player-controls__left > button:nth-child(2)').click();
  },
  pause: function () {
      if (BSStrategy.isPlaying()) {
          document.querySelector('div.player-controls__buttons button[data-testid="control-button-playpause"]').click();
      }
  },
  trackInfo: function () {
    return {
      'image': document.querySelector('div.Root__now-playing-bar img[data-testid="cover-art-image"]').src,
      'track': document.querySelector('div.Root__now-playing-bar a[data-testid="context-item-link"]').textContent,
      'artist': document.querySelector('div.Root__now-playing-bar div[data-testid="context-item-info-subtitles"]').textContent,
      'favorited': !!(document.querySelector('div.control-button.control-button-heart > button.a65d8d62fe56eed3e660b937a9be8a93-scss'))
    };
  }
}
