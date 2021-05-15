//
//  Spotify.plist
//  BeardedSpice
//
//  Created by Jose Falcon on 12/19/13.
//  Modified by Roman Spkolov on 05/13/2021
//  Copyright (c) 2021 GPL v3 http://www.gnu.org/licenses/gpl.html
//
BSStrategy = {
  version:3,
  displayName:"Spotify",
  homepage: 'https://spotify.com/',
  accepts: {
    method: "predicateOnTab",
    format:"%K LIKE[c] '*open.spotify.com*'",
    args: ["URL"]
  },
  isPlaying: function() {
    return !!(document.querySelector('div.player-controls__buttons button[data-testid="control-button-pause"]'));
  },
  toggle: function () {
    (document.querySelector('div.player-controls__buttons button[data-testid="control-button-play"]') 
    || document.querySelector('div.player-controls__buttons button[data-testid="control-button-pause"]')).click();
  },
  next: function () {
    document.querySelector('div.player-controls__buttons button[data-testid="control-button-skip-forward"]').click();
  },
  favorite: function () {
    document.querySelector('div.control-button.control-button-heart > button').click()    
  },
  previous: function () {
    document.querySelector('div.player-controls__buttons > button:nth-child(2)').click();
  },
  pause: function () {
    document.querySelector('div.player-controls__buttons button[data-testid="control-button-pause"]').click();
  },
  trackInfo: function () {
    return {
      'image': document.querySelector('div.Root__now-playing-bar img[data-testid="cover-art-image"]').src,
      'track': document.querySelector('div.Root__now-playing-bar a[data-testid="nowplaying-track-link"]').textContent,
      'artist': document.querySelector('div.Root__now-playing-bar div[data-testid="track-info-artists"]').textContent,
      'favorited': !!(document.querySelector('div.control-button.control-button-heart > button.a65d8d62fe56eed3e660b937a9be8a93-scss'))
    };
  }
}
