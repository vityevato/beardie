//
//  Vimeo.plist
//  BeardedSpice
//
//  Created by Antoine Hanriat on 08/08/14.
//  Modified by Roman Spkolov on 05/14/2021
//  Copyright (c) 2021 GPL v3 http://www.gnu.org/licenses/gpl.html
//
BSStrategy = {
  version:2,
  displayName:"Vimeo",
  homepage: "https://vimeo.com/",
  accepts: {
    method: "predicateOnTab",
    format:"%K LIKE[c] '*vimeo.com*'",
    args: ["URL"]
  },
  isPlaying: function () {return !!(document.querySelector('div.vp-controls > button.play.state-playing'))},
  toggle: function () {document.querySelector('div.vp-controls > button.play').click()},
  pause: function () {
    let elem = document.querySelector('div.vp-controls > button.play.state-playing');
    if (elem) {
      elem.click();
      return true;
    }
    return false;
  },
  trackInfo: function () {
    return {
      'track': document.querySelector('span.-KXLs').textContent,
      'artist': document.querySelector('div._1D7gj a.js-user_link').textContent,
      'image': document.querySelector('div._1Mv4b img').src
    };
  }
}
