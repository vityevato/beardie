//
//  Deezer.plist
//  BeardedSpice
//
//  Created by Greg Woodcock on 06/01/2015.
//  Copyright (c) 2015 Tyler Rhodes / Jose Falcon. All rights reserved.
//

BSStrategy = {
  version: 4,
  displayName: "Deezer",
  homepage: "https://www.deezer.com/",
  accepts: {
    method: "predicateOnTab",
    format: "%K LIKE[c] '*deezer.com*'",
    args: ["URL"]
  },
  isPlaying: function() {
    return dzPlayer.isPlaying();
  },
  toggle: function () {
    dzPlayer.control.togglePause();
  },
  next: function () {
    if (dzPlayer.getMediaType() == 'talk') {
      let button = document.querySelector("#page_player div.player-controls button.svg-icon-group-btn > svg.svg-icon-next-30");
      button && button.parentElement.click();
      return;
    }
    dzPlayer.control.nextSong();
  },
  previous: function () {
    if (dzPlayer.getMediaType() == 'talk') {
      let button = document.querySelector("#page_player div.player-controls button.svg-icon-group-btn > svg.svg-icon-prev-30");
      button && button.parentElement.click();
      return;
    }
    dzPlayer.control.prevSong();
  },
  favorite: function (){
    BSStrategy.favButton().click() ;
  },
  pause: function () {
    dzPlayer.control.pause();
  },
  trackInfo: function () {
    let faved = false;
    try {
      let button = BSStrategy.favButton();
      if (button) { 
        faved = button.querySelector('svg.is-active') != null;
      }
    } catch (error) { }
    let data = dzPlayer.getCurrentSong();
    if (dzPlayer.getMediaType() == 'talk') {
      return {
        "track": data.EPISODE_TITLE,
        "artist": data.SHOW_NAME,
        "image": "https://e-cdns-images.dzcdn.net/images/talk/"+data.SHOW_ART_MD5+"/380x380-000000-80-0-0.jpg"
      };
    }
    return {
      "track": data.SNG_TITLE,
      "artist": data.ARTISTS.map(item => item.ART_NAME).join(', '),
      "album": data.ALB_TITLE,
      "image": "https://e-cdns-images.dzcdn.net/images/cover/"+data.ALB_PICTURE+"/380x380-000000-80-0-0.jpg",
      "favorited": faved
    };
  },
  // PRIVATE
  favButton: function() {
    return document.querySelector('#page_player div.player-full div.datagrid-row.song.active > div.cell-love > button') 
    || document.querySelector('#page_player div.track-actions button > svg.svg-icon-love-outline').parentElement;
  }
}
