//
//  Twitch.plist
//  BeardedSpice
//
//  Modified by Roman Spkolov on 05/14/2021
//  Copyright (c) 2021 GPL v3 http://www.gnu.org/licenses/gpl.html
//
BSStrategy = {
  version:2,
  displayName:"Twitch TV",
  homepage: "https://www.twitch.tv/",
  accepts: {
    method: "predicateOnTab",
    format: "%K LIKE[c] '*twitch.tv/*'",
    args: ["URL"]
  },
  isPlaying: function () {
    return BSStrategy.pVideo() != null;
  },
  toggle: function () {
    if (!BSStrategy.pause()) {
      let au = BSStrategy.lastPlayed || document.querySelectorAll('audio[src]')[0];
      if (au) au.play();
    }
  },
  pause: function () {
    let au = BSStrategy.pVideo();
    if (au != null) {
      au.pause();
      return true;
    }
    return false;
  },
  // custom (private)
  lastPlayed: null,
  lastControllerData: null,
  pVideo: function () {
    let video = document.querySelectorAll('video[src]');
    for (var i = 0; i < video.length; i++) {
      if (video[i].paused == false) {
        BSStrategy.lastPlayed = video[i];
        return BSStrategy.lastPlayed;
      }
    }
    return null;
  }
}
