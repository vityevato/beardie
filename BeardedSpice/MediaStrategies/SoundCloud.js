//
//  SoundCloud.plist
//  BeardedSpice
//
//  Created by Jose Falcon on 12/16/13.
//  Copyright (c) 2013 Tyler Rhodes / Jose Falcon. All rights reserved.
//
BSStrategy = {
  version:4,
  displayName:"SoundCloud",
  homepage: "https://soundcloud.com/",
  accepts: {
    method: "predicateOnTab",
    format:"%K LIKE[c] '*soundcloud.com*'",
    args: ["URL"]
  },
  isPlaying:function () {
    var play = document.querySelector('.playControl');
    return play.classList.contains('playing');
  },
  toggle: function () {return document.querySelectorAll('.playControl')[0].click()},
  next: function() {
    if (BSStrategy.isLongPlay()) { return !!(BSStrategy.seek(30));}
    else { return !!(document.querySelectorAll('.skipControl__next')[0].click());}
},
  previous: function() {
    if ( !BSStrategy.isLongPlay() || BSStrategy.seek(-30) < 0) 
      return !!(document.querySelectorAll('.skipControl__previous')[0].click());
    return true;
},
  favorite:function () {return document.querySelector('div.playControls button.playbackSoundBadge__like').click()},
  pause: function (){
      var play = document.querySelector('.playControl');
      if(play.classList.contains('playing')) { play.click(); }
  },
  trackInfo: function () {
    let result =  {
        'track': document.querySelector('a.playbackSoundBadge__titleLink.sc-truncate').title,
        'artist': document.querySelector('a.playbackSoundBadge__lightLink.sc-truncate').title,
        'image': document.querySelector('div.playControls span.sc-artwork').style['background-image'].slice(5, -2),
        'favorited': document.querySelector('div.playControls button.playbackSoundBadge__like').classList.contains('sc-button-selected')
    }
    if (BSStrategy.isLongPlay()) {
       result['progress'] = BSStrategy.passed() + ' of ' + BSStrategy.duration();
    }
    return result;
  },
  // custom (private)
  LONGPLAY_SECONRS: 900,
  hmsToSeconds: function (str) {
    var p = str.split(':'),
      s = 0, m = 1;

    while (p.length > 0) {
      s += m * parseInt(p.pop(), 10);
      m *= 60;
    }

    return s;
  },
  duration: function () {return document.querySelector('div.playControls__timeline div.playbackTimeline__duration > span:nth-child(2)').textContent;},
  passed: function () {return document.querySelector('div.playControls__timeline div.playbackTimeline__timePassed > span:nth-child(2)').textContent;},
  isLongPlay: function () {
    let duration = BSStrategy.duration();
    return (duration && BSStrategy.hmsToSeconds(duration) >= BSStrategy.LONGPLAY_SECONRS);
  },
  seek: function (offset) {
    let newPosition = BSStrategy.hmsToSeconds(BSStrategy.passed()) + offset;
    let timeEnd = BSStrategy.hmsToSeconds(BSStrategy.duration());
    if (newPosition > timeEnd) newPosition = timeEnd;
    let elem = document.querySelector('div.playControls__timeline div.playbackTimeline__progressWrapper');
    let elemRect = elem.getBoundingClientRect();
    let x = newPosition * elemRect.width / timeEnd + elemRect.x;
    let y = elemRect.y + elemRect.height / 2;
    let eventData = { 'view': window, 'bubbles': true, 'cancelable': true, 'clientX': x, 'clientY': y };
    elem.dispatchEvent((new MouseEvent('mousedown', eventData)));
    elem.dispatchEvent((new MouseEvent('mouseup', eventData)));
    return newPosition;
  },

}
