//
//  YandexMusic.plist
//  BeardedSpice
//
//  Created by Vladimir Burdukov on 3/14/14.
//  Updated by Ivan Tsyganov     on 2/13/18.
//  Updated by Arseny Mitin      on 11/18/18.
//  Copyright (c) 2014 Tyler Rhodes / Jose Falcon. All rights reserved.

BSStrategy = {
  version:5,
  displayName:"YandexMusic",
  homepage: "https://music.yandex.ru/",
  accepts: {
    method: "predicateOnTab",
    format:"%K LIKE[c] '*music.yandex.*'",
    args: ["URL"]
  },
  isPlaying: function () {return externalAPI.isPlaying();},
  toggle: function () {externalAPI.togglePause();},
  next: function () {
    if (BSStrategy.isPodcast()) {
      BSStrategy.seek(30);
    }
    else {
      externalAPI.next();
    }
  },
  favorite: function () {externalAPI.toggleLike();},
  previous: function () {
    if (BSStrategy.isPodcast()) {
      if (BSStrategy.seek(-30) < 0)
        externalAPI.prev();      
    }
    else {
      externalAPI.prev();
    }
  },
  pause: function () {
    if (self.isPlaying()){externalAPI.togglePause();}
  },
  trackInfo: function () {
    let result = {
      track:  externalAPI.getCurrentTrack().title,
      artist: externalAPI.getCurrentTrack().artists.map(item => item.title).join(', '),
      album: externalAPI.getCurrentTrack().album.title,
      favorited: externalAPI.getCurrentTrack().liked,
      image: externalAPI.getCurrentTrack().cover.replace('%%', '400x400')
    };
    if (BSStrategy.isPodcast()) {
      let progress = externalAPI.getProgress();
      let pos = (new Date(progress.position * 1000).toISOString().substr(11, 8)).replace(/00:(\d{2}:\d{2})/,'$1' ).replace(/0(\d:\d{2}:\d{2})/,'$1' );
      let dur = (new Date(progress.duration * 1000).toISOString().substr(11, 8)).replace(/00:(\d{2}:\d{2})/,'$1' ).replace(/0(\d:\d{2}:\d{2})/,'$1' );
      result.progress = pos + " of " + dur;
      result.artist = result.album;
      delete result.album;
    }
    return result;
  },
  // Private
  isPodcast: function () {
    return (document.querySelector("div.bar div.player-controls.player-controls_podcast") != null); 
  },
  seek: function(offset) {
    let progress = externalAPI.getProgress();
    let newPosition = progress.position + offset;
    if (newPosition > progress.duration) newPosition = progress.duration;
    externalAPI.setPosition(newPosition);
    return newPosition;
  }
}
