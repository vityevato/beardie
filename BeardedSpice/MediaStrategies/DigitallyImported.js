//
//  DigitallyImported.plist
//  BeardedSpice
//
//  Created by Dennis Lysenko on 4/4/15.
//  Copyright (c) 2015 Tyler Rhodes / Jose Falcon. All rights reserved.
//

BSStrategy = {
  version:3,
  displayName:"Digitally Imported",
  homepage: "https://www.di.fm",
  accepts: {
    method: "predicateOnTab",
    format:"%K LIKE[c] '*di.fm*'",
    args: ["URL"]
  },
  isPlaying:function () {
      var pause = $('#webplayer-region .controls .ico.icon-pause').length;
      var spinner = $('#webplayer-region .controls .ico.icon-spinner3').length;
      var sponsor = $('#webplayer-region .metadata-container .track-title .sponsor').length;
      return pause ? true : (spinner && sponsor);
  },
  toggle: function () { return document.querySelectorAll('div.controls a')[0].click() },
  next: function () {
    document.querySelector('#webplayer-region div.skip-button > div > div.skip-button').click()
  },
  favorite: function () { $('#webplayer-region .track-voting-component__up').get(0).click(); },
  pause:function () {
    var pause = document.querySelectorAll('div.controls a')[0];
    if(pause.classList.contains('icon-pause')){
      pause.click();
    }
  },
  trackInfo: function () {
    var artistName = $('.artist-name').text();
    var trackName = $('.track-name').text().replace(artistName, "");
    if (artistName.length > 3) {
        artistName = artistName.substring(0, artistName.length - 3);
    }
    return {
      'artist': artistName,
      'track': trackName.replace(/\s+/, ''),
      'favorited': ($('#webplayer-region .track-voting-component__up.active').get(0) ? true : false),
      'image': $('#webplayer-region .track-region .artwork img').attr('src')
    }
  }
}
