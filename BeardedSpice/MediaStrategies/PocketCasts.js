//
//  PocketCasts.plist
//  BeardedSpice
//
//  Created by Dmytro Piliugin on 1/23/15.
//  Modified by Roman Sokolov on 5/11/21
//  Copyright (c) 2021 GPL v3 http://www.gnu.org/licenses/gpl.html
//
BSStrategy = {
  version:3,
  displayName:"Pocket Casts",
  homepage: "https://play.pocketcasts.com/",
  accepts: {
    method: "predicateOnTab",
    format:"%K LIKE[c] '*play.pocketcasts.com*'",
    args: ["URL"]
  },
  toggle: function () {document.querySelector('button.play_pause_button').click()},
  next: function () {document.querySelector('button.skip_forward_button').click()},
  previous: function () {document.querySelector('button.skip_back_button').click()},
  pause: function () {if (BSStrategy.isPlaying()) BSStrategy.toggle();},
  trackInfo: function () {
    return {
      'track': document.querySelector('div.controls-center .player_episode').innerText,
      'artist': document.querySelector('div.controls-center .player_podcast_title').innerText,
      'progress': document.querySelector('div.controls div.controls-center div.current-time').textContent + ' of ' + document.querySelector('div.controls div.controls-center div.time-remaining').textContent.replace(/^-/,''),
      'image': document.querySelector('button.player-image img').src,
    };
  },
  isPlaying: function () {
    let audio = document.querySelectorAll('audio[src]');
    for(var i = 0; i < audio.length; i++) {
        if (audio[i].paused == false) { return true;}
    }
    return false;
  }
}
