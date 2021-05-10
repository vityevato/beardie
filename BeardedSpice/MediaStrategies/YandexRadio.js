//
//  YandexMusic.plist
//  BeardedSpice
//
//  Created by Leonid Ponomarev 15.06.15
//  Updated by Ivan Tsyganov    13.02.18
//  Updated by Arseny Mitin     18.11.18
//  Updated by Roman Sokolov     on 05/07/21.
//  Copyright (c) 2021 GPL v3 http://www.gnu.org/licenses/gpl.html

BSStrategy = {
  version:5,
  displayName:"Yandex Radio",
  homepage: "https://radio.yandex.ru/",
  accepts: {
    method: "predicateOnTab",
    format:"%K LIKE[c] '*radio.yandex.*'",
    args: ["URL"]
  },
  isPlaying: function () {return externalAPI.isPlaying();},
  toggle: function () {externalAPI.togglePause();},
  next: function () {externalAPI.next();},
  favorite: function () {externalAPI.toggleLike();},
  previous: function () {},
  pause: function () {
    if (BSStrategy.isPlaying()){externalAPI.togglePause();}
  },
  trackInfo: function () {
    return {
      track:  externalAPI.getCurrentTrack().title,
      artist: externalAPI.getCurrentTrack().artists.map(item => item.title).join(', '),
      favorited: externalAPI.getCurrentTrack().liked,
      image: externalAPI.getCurrentTrack().cover.replace('%%', '400x400')
    };
  }
}
