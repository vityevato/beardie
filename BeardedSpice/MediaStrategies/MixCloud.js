//
//  MixCloud
//  BeardedSpice
//
//  Created by Roman Sokolov.
//  Copyright (c) 2015-2020 GPL v3 http://www.gnu.org/licenses/gpl.html
//
BSStrategy = {
  version:6,
  displayName:"Mixcloud",
  accepts: {
    method: "predicateOnTab",
    format:"%K LIKE[c] '*www.mixcloud.com*'",
    args: ["URL"]
  },
  isPlaying: function() {return (BSStrategy.pauseButton() != null)},
  pause: function () { BSStrategy.pauseButton().click() },
  toggle: function () { ( BSStrategy.pauseButton() || BSStrategy.playButton()).click(); },
  next: function() {document.querySelector('button[aria-label="Seek forwards"]').click()},
  previous: function() {document.querySelector('button[aria-label="Seek backwards"]').click()},
  favorite: function() {document.querySelector('span[class*="PlayerActionsFavoriteButton__PlayerFavoriteIcon-"]').click()},
  trackInfo: function () {
    return {
      'track': document.querySelector('p[class*="PlayerControls__ShowTitle-"]').textContent,
      'artist': document.querySelector('span[class*="PlayerControls__ShowOwnerName-"]').textContent,
      'image' : document.querySelector('div[class*="PlayerControls__ShowPicture-"]>img').currentSrc,
      'progress': document.querySelector('div[class*="PlayerSliderComponent__StartTime-"]').textContent + '( remains ' + document.querySelector('div[class*="PlayerSliderComponent__EndTime-"]').textContent + ')',
      'favorited': (document.querySelector('span[class*="PlayerActionsFavoriteButton__PlayerFavoriteIcon-"]').getAttribute('data-tooltip') == "Undo Favorite")
    };
  },
  pauseButton: function() {return document.querySelector('div[aria-label="Pause"]') || document.querySelector('.shaka-play-button[icon="pause"]'); },
  playButton: function() {return document.querySelector('div[aria-label="Play"]') || document.querySelector('.shaka-play-button[icon="play"]'); }
}
