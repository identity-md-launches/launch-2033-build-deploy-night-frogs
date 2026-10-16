#!/usr/bin/env python3
"""Original NIGHT FROGS vector masters and deterministic SSTORE2 packer. Stdlib only.
Run from the repository root. No downloaded artwork, fonts, or external references.
"""
from pathlib import Path
import json
import math

ROOT = Path(__file__).resolve().parents[1]
ART = ROOT / 'art'
ART.mkdir(exist_ok=True)
OUT = ROOT / 'src/art'
OUT.mkdir(exist_ok=True)

def path(d, fill='none', extra=''):
    return f'<path d="{d}" fill="{fill}" {extra}/>'

def text(x, y, value, size=28, fill='#F2EFFF', extra=''):
    return f'<text x="{x}" y="{y}" font-size="{size}" fill="{fill}" stroke="none" {extra}>{value}</text>'

def circle(x,y,r,fill,extra=''):
    return f'<circle cx="{x}" cy="{y}" r="{r}" fill="{fill}" {extra}/>'

def rect(x,y,w,h,fill,extra=''):
    return f'<rect x="{x}" y="{y}" width="{w}" height="{h}" fill="{fill}" {extra}/>'

INK='#08070D'
ACID='#B8FF4A'
GOLD='#FFC46B'
MOON='#C4B4FF'
CYAN='#3FE6FF'
MAGENTA='#FF4FD8'

head='M230 555Q207 481 278 423C264 330 309 269 382 269C438 269 482 302 497 352C513 299 553 269 609 269C691 269 731 340 712 431Q802 488 777 588Q806 699 687 742Q612 782 487 765Q344 783 260 711Q204 656 230 555Z'
body='M126 1010L145 855Q158 774 294 741L359 704H641L705 741Q842 772 859 855L882 1010Z'
base_style='''<style>text{font-family:monospace;font-weight:700;letter-spacing:2px}.line{stroke:#08070D;stroke-width:12;stroke-linejoin:round;stroke-linecap:round}.fine{stroke-width:6}.rim{fill:none;stroke:currentColor;stroke-width:10;stroke-linecap:round}.skin{fill:#5F9E45}.shade{fill:#3B6638}.light{fill:#8DC665}</style>'''
defs='''<defs>
<radialGradient id="night"><stop stop-color="#35205B"/><stop offset="1" stop-color="#03020A"/></radialGradient>
<radialGradient id="vignette"><stop offset=".52" stop-color="#03020A" stop-opacity="0"/><stop offset="1" stop-color="#03020A" stop-opacity=".78"/></radialGradient>
<linearGradient id="chrome" x2=".85" y2="1"><stop stop-color="#F2EFFF"/><stop offset=".3" stop-color="#6D81A0"/><stop offset=".48" stop-color="#D4FAFF"/><stop offset=".5" stop-color="#34405E"/><stop offset=".75" stop-color="#899AB9"/><stop offset="1" stop-color="#E9F4FF"/></linearGradient>
<linearGradient id="fog" x2="0" y2="1"><stop stop-color="#7C5CFF" stop-opacity="0"/><stop offset=".6" stop-color="#7C5CFF" stop-opacity=".2"/><stop offset="1" stop-color="#03020A" stop-opacity="0"/></linearGradient>
<filter id="glow" x="-80%" y="-80%" width="260%" height="260%"><feGaussianBlur stdDeviation="9"/></filter>
<filter id="grain"><feTurbulence type="fractalNoise" baseFrequency=".72" numOctaves="3" stitchTiles="stitch"/><feColorMatrix type="saturate" values="0"/></filter>
<clipPath id="eyeL"><ellipse cx="391" cy="390" rx="92" ry="85"/></clipPath>
<clipPath id="eyeR"><ellipse cx="601" cy="390" rx="92" ry="85"/></clipPath>
'''
defs+='<g id="frog-head" class="line">'+path(head,'#08070D', 'transform="translate(20 17)" opacity=".35"')+path(head,'#5F9E45','class="skin"')
defs+=path('M731 453Q790 510 769 592Q784 688 678 727Q579 762 471 744Q313 757 258 681Q353 728 491 707Q643 725 705 631Q756 559 731 453Z','#3B6638','class="shade" stroke="none"')
defs+=path('M257 551Q242 487 300 445L306 351Q319 291 381 288Q438 288 469 341','none','class="rim"')
defs+=path('M529 327Q572 284 620 290','none','stroke="#F2EFFF" stroke-width="6" opacity=".18"')
defs+=path('M286 563Q302 524 357 519Q388 517 400 542Q355 526 319 558Z','#8DC665','class="light" stroke="none"')
defs+=path('M442 535Q449 523 459 533M520 532Q533 521 539 536','none','stroke-width="9"')
defs+=path('M434 558Q484 574 548 554','none','stroke-width="5" opacity=".32"')
defs+=path('M272 590Q252 623 270 652M728 586Q745 613 732 641','none','stroke-width="6" opacity=".55"')
defs+='</g>'
# Shared eyes. Lid color inherits each skin palette; all eye equipment shares this anchor.
defs+='<g id="whites" class="line"><ellipse cx="391" cy="390" rx="92" ry="85" fill="#EEE6BC"/><ellipse cx="601" cy="390" rx="92" ry="85" fill="#EEE6BC"/></g>'
defs+='<g id="pupils"><g clip-path="url(#eyeL)"><ellipse cx="427" cy="414" rx="25" ry="34" fill="#08070D"/>'+circle(436,431,8,'#FFFFFF')+'</g><g clip-path="url(#eyeR)"><ellipse cx="637" cy="414" rx="25" ry="34" fill="#08070D"/>'+circle(646,431,8,'#FFFFFF')+'</g></g>'
defs+='<g id="lids" class="line"><path class="skin" d="M299 381C304 329 338 302 384 305Q464 298 482 414Q391 406 299 381Z"/><path class="skin" d="M509 381C514 329 548 302 594 305Q674 298 692 414Q601 406 509 381Z"/><path d="M315 475Q384 506 465 480M525 475Q594 506 675 480" fill="none" stroke-width="7" opacity=".65"/><path d="M315 354Q359 318 404 333M525 354Q569 318 614 333" fill="none" stroke="#F2EFFF" stroke-width="6" opacity=".15"/></g>'
defs+='<g id="tired"><use href="#whites"/><use href="#pupils"/><use href="#lids"/></g>'
defs+='</defs>'
# Edge print lives after the character and texture. Deliberately compact labels, bold portrait.
finish=rect(0,0,1000,1000,'url(#vignette)','stroke="none"')+rect(0,0,1000,1000,'#FFFFFF','filter="url(#grain)" opacity=".035" stroke="none"')
finish+=path('M46 171V46H172M828 46H954V171M46 830V954H170M830 954H954V830','none','stroke="currentColor" stroke-width="3" opacity=".65"')
finish+=text(72,99,'NIGHTSHIFT',40)+text(72,134,'AUTONOMOUS / AFTER HOURS',15,MOON)
finish+=text(925,99,'03:00',32,GOLD,'text-anchor="end"')+text(925,128,'UTC // ON DUTY',14,MOON,'text-anchor="end"')
finish+=rect(60,899,880,64,'#08070D','rx="9" stroke="currentColor" stroke-width="2"')+text(83,940,'NIGHT FROGS',32)+text(916,938,'ALWAYS SHIPPING',20,MOON,'text-anchor="end"')
placeholder=rect(0,0,1000,1000,'url(#night)')+circle(500,478,235,'none','stroke="#7C5CFF" stroke-width="2" stroke-dasharray="4 17"')
placeholder+=path('M566 267A190 190 0 1 0 649 586A170 170 0 0 1 566 267Z',MOON,'stroke="#08070D" stroke-width="12"')
placeholder+=path('M384 386Q355 441 365 489','none','stroke="#F2EFFF" stroke-width="8"')+text(500,766,'THE CREW IS CLOCKING IN',29,'#F2EFFF','text-anchor="middle"')+text(500,807,'AWAITING THE FIRST WATCH',18,MOON,'text-anchor="middle"')
unique='<g class="line">'+path('M694 511L668 540L694 569L669 595','none','stroke="#FFC46B" stroke-width="13"')+path('M325 776L365 806L325 839L285 806Z',GOLD)+text(325,818,'I',31,INK,'text-anchor="middle"')+rect(679,727,213,64,INK,'rx="10" stroke="#FFC46B" stroke-width="5"')+text(787,766,'NO SLEEP',23,GOLD,'text-anchor="middle"')+'</g>'

backgrounds=[]
# Neon city: hand-shaped skyline, staggered lit windows, low fog.
s=rect(0,0,1000,1000,'url(#night)')+circle(800,270,162,MAGENTA,'opacity=".13"')
for x,y,w in [(0,400,115),(122,305,128),(266,456,95),(695,349,102),(815,285,87),(911,420,100)]:
    s+=rect(x,y,w,540,'#100D24','stroke="#393253" stroke-width="4"')+rect(x+8,y,w-16,5,CYAN,'opacity=".7"')
    for j in range(4):
        for k in range(2):
            s+=rect(x+20+k*43,y+35+j*65,17,26, CYAN if (j+k)%3 else MAGENTA,'opacity=".7"')
s+=rect(0,590,1000,300,'url(#fog)')+text(112,263,'OPEN 24/7',24,MAGENTA)
backgrounds.append(('Neon City',30,s,CYAN))
s=rect(0,0,1000,1000,'url(#night)')
for x,y in [(0,242),(660,240),(70,536)]:
    s+=path(f'M{x} {y}q100 -94 195 0q67 -90 151 -9q73 -21 120 62H{x}Z','#382358','opacity=".65"')
s+=path('M175 260L112 420L203 403L136 596M852 312L790 460L869 446L811 642','none','stroke="#7C5CFF" stroke-width="32" filter="url(#glow)"')
s+=path('M175 260L112 420L203 403L136 596M852 312L790 460L869 446L811 642','none','stroke="#C4B4FF" stroke-width="8"')
backgrounds.append(('Ultraviolet Storm',20,s,'#7C5CFF'))
s=rect(0,0,1000,1000,'#080C22')+path('M835 156A175 175 0 1 0 879 447A150 150 0 0 1 835 156Z',MOON)
for x,y,r in [(128,224,4),(245,187,3),(591,191,5),(89,497,3),(909,559,4),(782,590,3),(135,667,3)]: s+=circle(x,y,r,'#F2EFFF')
s+=path('M0 765Q200 664 397 730T1000 700V1000H0Z','#15192F')
backgrounds.append(('Moonlit Sky',20,s,MOON))
s=rect(0,0,1000,1000,'#03020A')+path('M40 800Q480 240 940 180','none','stroke="#40266D" stroke-width="150" opacity=".2"')
for i in range(35):
    x=65+(i*173)%870;y=180+(i*97)%590
    s+=circle(x,y,2+i%3,MOON if i%2 else '#F2EFFF','opacity=".8"')
s+=path('M115 307H165M140 282V332M806 589H844M825 570V608','none','stroke="#3FE6FF" stroke-width="4"')
backgrounds.append(('Deep Starfield',20,s,CYAN))
s=rect(0,0,1000,1000,'#070C13')+path('M0 150L370 370H630L1000 150M0 950L370 600H630L1000 950','none','stroke="#3FE6FF" stroke-width="6" opacity=".4"')
leds=''
for x in [28,172,746,890]:
    s+=rect(x,230,104,540,'#121D29','rx="8" stroke="#344858" stroke-width="5"')
    for y in range(258,750,69):
        s+=rect(x+12,y,80,48,'#080D16','rx="4"')+rect(x+21,y+15,35,4,'#546276')
        leds+=circle(x+74,y+23,5,ACID if y%2 else CYAN)
s+='<g>'+leds+'<animate attributeName="opacity" values="1;.25;1" dur="1.8s" repeatCount="indefinite"/></g>'
s+=text(500,201,'IMD // SWARM CORE',24,CYAN,'text-anchor="middle"')
backgrounds.append(('Server Corridor',10,s,ACID))
s=rect(0,0,1000,1000,'#1C1015')
for angle in range(0,360,20):
    s+=path('M500 468L430 -200L570 -200Z',GOLD,f'opacity=".1" transform="rotate({angle} 500 468)"')
s+=circle(500,468,334,'none','stroke="#FFC46B" stroke-width="8" stroke-dasharray="1 24" stroke-linecap="round"')+circle(500,468,359,'none','stroke="#FFC46B" stroke-width="2" opacity=".4"')
s+=text(111,607,'GENESIS',38,GOLD,'text-anchor="middle" transform="rotate(-90 111 607)"')
backgrounds.append(('Genesis Sunburst',100,s,GOLD))

bodies=[]
for name,weight,color,shadow,kind in [('Black Hoodie',30,'#191A24','#101018','hood'),('Purple Hoodie',23,'#52308C','#30204E','hood'),('Hi-vis Safety Vest',18,'#EA743A','#A83D2D','vest'),('Grey Work Jacket',15,'#5C6574','#343A48','jacket'),('NIGHTSHIFT Jumpsuit',11,'#293C51','#182534','crew'),('Gold Tracksuit',3,'#C89644','#795125','gold')]:
    s='<g class="line">'+path(body,color)+path('M665 775Q809 816 802 1010H882L859 855Q842 785 705 741Z',shadow,'stroke="none"')
    s+=path('M157 947L176 854Q185 801 292 765','none','class="rim"')+path('M252 890L236 1010M744 889L760 1010','none','stroke-width="8"')
    if kind=='hood':
        s+=path('M315 742Q322 699 376 690L500 755L624 690Q678 699 685 742L622 849L500 796L378 849Z',shadow)+path('M400 807L390 903M600 807L610 903','none','stroke="#C4B4FF" stroke-width="7"')+circle(391,900,8,'#C4B4FF')+circle(609,900,8,'#C4B4FF')
        s+=text(500,870,'NIGHTSHIFT',27,'#F2EFFF','text-anchor="middle"')
    elif kind=='vest':
        s+=path('M365 731L453 810V1010H547V810L635 731L600 709H400Z','#161B25')+path('M297 756L334 1010M703 756L666 1010','none','stroke="#D6E3BA" stroke-width="39"')+path('M164 862H837','none','stroke="#D6E3BA" stroke-width="32"')+text(500,860,'OPS',34,ACID,'text-anchor="middle"')
    elif kind=='jacket':
        s+=path('M352 724L500 791L422 843L314 752M648 724L500 791L578 843L686 752',shadow)+path('M500 794V1010M296 847H427V916H296ZM574 847H704V916H574Z','none','stroke-width="7"')+circle(520,853,7,GOLD)+circle(520,891,7,GOLD)
    elif kind=='crew':
        s+=path('M350 734L420 800H580L650 734','none','stroke="#C4B4FF" stroke-width="20"')+path('M500 801V1010','none','stroke="#778E9E" stroke-width="7"')+circle(641,847,42,'#171429')+path('M649 818A28 28 0 1 0 663 863A25 25 0 0 1 649 818Z',MOON,'stroke="none"')+text(316,863,'N/SHIFT',23)
    else:
        s+=path('M354 727L500 794L646 727M500 795V1010','none','stroke="#FFF0B5" stroke-width="16"')+path('M217 796L183 1010M247 783L215 1010M783 796L817 1010M753 783L785 1010','none','stroke="#F4DEA0" stroke-width="9"')+text(624,861,'NS',38,'#FFF0B5')
    s+='</g>'; bodies.append((name,weight,s))

skins=[]
for name,weight,base,shade,light in [('Classic Green',35,'#5F9E45','#3B6638','#8DC665'),('Dark Green',20,'#355A3C','#203B32','#62805B'),('Acid Neon',15,'#B8FF4A','#5EAB35','#DAFF94'),('Mint Zombie',5,'#91C9A8','#487D70','#C7E9CF'),('Ice Blue',10,'#78BED2','#3F728D','#B9E6EC'),('Purple Alien',10,'#9270BA','#563C79','#C3A4E1'),('Gold',4,'#D6A44A','#8D582E','#FFE298'),('Chrome',1,'url(#chrome)','#4D6480','#D9FFFF')]:
    s=f'<style>.skin{{fill:{base}}}.shade{{fill:{shade}}}.light{{fill:{light}}}</style><use href="#frog-head"/>'
    if name=='Mint Zombie': s+=path('M268 579L308 611M270 593L285 577M287 608L305 591','none','stroke="#203B32" stroke-width="7"')
    if name=='Chrome': s+=path('M266 554L284 531M691 650L715 625','none','stroke="#F2EFFF" stroke-width="8"')
    skins.append((name,weight,s))

mouths=[]
def lips(d,inner,detail=''):
    return '<g class="line">'+path(d,'#B05A44')+path(inner,'none','stroke="#6E2E22" stroke-width="13"')+path('M352 612Q397 598 443 607','none','stroke="#DA9274" stroke-width="8" opacity=".7"')+detail+'</g>'
mouths.append(('Corner Smirk',28,lips('M313 611Q353 578 446 592Q562 618 689 575Q707 603 678 625Q609 675 443 666Q345 664 313 635Z','M327 624Q483 657 687 596',path('M688 574Q706 576 714 592','none','stroke-width="7"'))))
mouths.append(('Toothpick',20,lips('M312 603Q384 580 483 594Q602 580 688 609L678 655Q492 682 323 652Z','M327 628Q493 640 678 630',path('M641 629L758 569','none','stroke="#EFD9A0" stroke-width="9"'))))
s='<g class="line">'+path('M311 592Q463 624 691 580Q698 679 573 702Q404 721 326 651Z','#B05A44')+path('M331 611Q505 644 672 600Q645 670 552 679Q398 688 348 639Z','#EEE6BC')+path('M355 642Q506 671 645 633M395 625L402 660M448 633L450 671M501 637V677M555 631L555 674M607 620L600 658','none','stroke-width="5"')+'</g>'
mouths.append(('Big Grin',15,s))
s='<g class="line">'+path('M376 610Q390 563 478 576Q570 577 597 620Q626 707 518 719Q400 727 376 658Z','#B05A44')+path('M401 620Q471 595 569 624Q580 689 510 695Q420 700 401 648Z','#291722')+path('M437 684Q463 649 492 669Q519 646 547 681','#A75661','stroke-width="5"')+path('M407 604Q435 590 464 597','none','stroke="#DA9274" stroke-width="8"')+'</g>'
mouths.append(('3 AM Yawn',12,s))
mouths.append(('Knowing Smile',18,lips('M314 612Q358 581 447 604Q548 631 689 592Q701 632 670 657Q551 706 393 672Q329 661 314 639Z','M331 624Q497 680 680 617')))
s='<g class="line">'+path('M317 605Q483 565 688 612L679 670Q509 645 322 674Z','#B05A44')+path('M336 622Q500 596 670 625L664 650Q495 626 337 653Z','#EEE6BC')+path('M377 617V647M422 612V642M469 612V639M516 613V640M563 615V641M610 618V645','none','stroke-width="5"')+'</g>'
mouths.append(('Gritted Teeth',7,s))

eyes=[]
eyes.append(('Heavy Lids',38,'<use href="#tired"/>'))
s='<use href="#tired"/><g stroke-linecap="round">'
for x in [427,637]:
    s+=circle(x,428,22,'#FF4F68','filter="url(#glow)"')+path(f'M{x} 428L{x+270} 480','none','stroke="#FF2C69" stroke-width="25" opacity=".6" filter="url(#glow)"')+path(f'M{x} 428L{x+270} 480','none','stroke="#FF607B" stroke-width="8"')+circle(x,428,10,'#FFF0F3')
s+='</g>';eyes.append(('Laser Eyes',7,s))
s='<use href="#tired"/><g class="line">'+path('M284 353L481 370L471 454Q355 486 301 430ZM508 370L708 353L690 431Q634 486 520 454Z','#101420')+path('M480 388Q494 374 511 388M284 366L259 359M708 366L734 359','none')+path('M319 369L373 446M346 370L398 448M549 383L593 450M576 379L621 452','none','stroke="#3FE6FF" stroke-width="15" opacity=".65"')+'</g>'
eyes.append(('Neon Shades',16,s))
s='<use href="#tired"/><g class="line">'+rect(276,344,443,125,'#103E50','rx="30" stroke="#3FE6FF" stroke-width="12"')+rect(295,361,407,90,'#1F8FAD','rx="20" stroke="none" opacity=".55"')
for y in range(369,449,16): s+=path(f'M300 {y}H694','none','stroke="#3FE6FF" stroke-width="3" opacity=".7"')
s+=text(498,422,'SYSTEM ONLINE',27,'#B5FFFF','text-anchor="middle"')+path('M276 380L250 375M719 380L744 375','none')+'</g>';eyes.append(('Cyan VR Visor',8,s))
s='<use href="#whites"/><g class="line" stroke="#B85450" stroke-width="5">'+path('M311 364L345 379L333 395M321 437L353 418L359 444M462 358L444 387M517 360L553 381L538 398M528 442L565 423L572 450M676 355L659 381','none','stroke="#B85450" stroke-width="5"')+'</g><g>'+circle(414,395,22,INK)+circle(624,395,22,INK)+circle(421,387,7,'#FFFFFF')+circle(631,387,7,'#FFFFFF')+'</g>'+path('M308 488Q371 517 459 490M518 488Q581 517 669 490','none','stroke="#08070D" stroke-width="8"')
eyes.append(('Wired',12,s))
s='<use href="#tired"/><g class="line">'+path('M509 381C514 329 548 302 594 305Q684 298 693 418Q691 470 603 474Q533 475 509 428Z','#5F9E45','class="skin"')+path('M528 424Q603 451 680 418','none','stroke-width="10"')+path('M540 416L531 437M666 414L675 430','none','stroke-width="6"')+'</g>';eyes.append(('Deadpan Wink',10,s))
s='<use href="#whites"/>'+circle(391,400,64,ACID,'filter="url(#glow)" opacity=".6"')+circle(601,400,64,ACID,'filter="url(#glow)" opacity=".6"')+circle(391,400,64,ACID)+circle(601,400,64,ACID)+path('M408 385V442M618 385V442','none','stroke="#13251A" stroke-width="18"')+'<use href="#lids"/>';eyes.append(('Acid Glow',7,s))
s='<use href="#tired"/>'+circle(601,405,91,'#C4B4FF','fill-opacity=".13" stroke="#FFC46B" stroke-width="12"')+path('M685 441Q769 531 731 688L744 734','none','stroke="#FFC46B" stroke-width="7"')+path('M555 354L594 390','none','stroke="#F2EFFF" stroke-width="8" opacity=".7"');eyes.append(('Monocle',2,s))

headwear=[]
s='<g class="line">'+path('M294 291Q310 182 500 181Q689 182 706 291Z','#E9AC35')+path('M311 281Q332 210 422 202L406 281Z','#FFD966','stroke="none"')+path('M466 187H536V285H466Z','#C78729','stroke-width="7"')+path('M277 279Q499 257 724 279L739 311Q501 335 262 312Z','#FFC84F')+rect(462,258,79,62,'#353D4B','rx="12"')+circle(500,286,22,'#F2EFFF','stroke="#3FE6FF" stroke-width="7"')+path('M484 276L55 162L53 355L484 299Z','#FFF2AA','opacity=".16" stroke="none"')+'</g>';headwear.append(('Headlamp Hard Hat',20,s))
s='<g class="line">'+path('M297 286Q299 180 500 178Q691 181 706 285Z','#49385E')+circle(500,174,43,'#8B6A9C')+path('M316 268Q499 241 689 268L713 314Q496 298 285 314Z','#755585')+path('M334 273L330 302M371 267L368 298M410 263L409 296M449 260V294M490 259V292M531 260V294M572 263L573 296M612 267L615 298M652 273L658 302','none','stroke="#A586AF" stroke-width="7"')+rect(456,267,86,40,'#161223','rx="3" stroke-width="5"')+text(500,295,'3AM',23,'#F2EFFF','text-anchor="middle"')+'</g>';headwear.append(('Night Beanie',20,s))
s='<g class="line">'+path('M273 425Q235 213 490 220Q752 213 730 425','none','stroke="#08070D" stroke-width="30"')+path('M271 338Q294 234 398 237','none','stroke="#7C5CFF" stroke-width="12"')+rect(247,381,53,124,'#262638','rx="22"')+rect(701,381,53,124,'#262638','rx="22"')+path('M733 497Q767 598 653 625','none','stroke="#08070D" stroke-width="15"')+rect(622,607,60,30,'#3FE6FF','rx="15" stroke-width="7"')+path('M266 409V473M734 409V473','none','stroke="#7C5CFF" stroke-width="7"')+'</g>';headwear.append(('Dispatcher Headset',17,s))
s='<g class="line">'+path('M326 291L302 192L392 230L446 155L501 228L559 155L613 230L702 192L677 291Z','#FFC46B')+path('M327 278Q500 258 676 278L676 313Q500 289 327 313Z','#BB772F')
for x,c in [(382,MAGENTA),(500,CYAN),(622,ACID)]:s+=path(f'M{x} 247l14 17l-14 17l-14 -17Z',c,'stroke-width="5"')
s+='</g>';headwear.append(('Gold Crown',3,s))
s='<g class="line">'+path('M302 288Q333 188 500 189Q676 185 698 292Z','#26464B')+path('M364 215Q396 253 390 293','none','stroke="#487477" stroke-width="6"')+path('M301 275Q502 254 700 277L701 314Q509 289 297 315Z','#41656C')+path('M298 277Q194 242 183 286Q186 333 300 314Z','#213337')+rect(467,268,79,35,'#0F1B26','rx="9" stroke-width="5"')+path('M485 285H530','none','stroke="#FFC46B" stroke-width="6"')+'</g>';headwear.append(('Backwards Cap',17,s))
s='<g class="line">'+path('M287 292Q501 250 708 292','none','stroke="#161E25" stroke-width="36"')+rect(355,243,126,81,'#303F42','rx="21"')+rect(519,243,126,81,'#303F42','rx="21"')+path('M481 274H519','none','stroke-width="20"')+circle(419,283,31,'#95E63E','stroke-width="7"')+circle(582,283,31,'#95E63E','stroke-width="7"')+circle(419,283,16,'#314933','stroke="none"')+circle(582,283,16,'#314933','stroke="none"')+path('M405 269L421 284M568 269L584 284','none','stroke="#D5FFAF" stroke-width="6"')+'</g>';headwear.append(('Night Vision',8,s))
s='<ellipse cx="500" cy="220" rx="190" ry="37" fill="none" stroke="#C4B4FF" stroke-width="22" filter="url(#glow)"/><ellipse cx="500" cy="220" rx="190" ry="37" fill="none" stroke="#F2EFFF" stroke-width="9"/>'+path('M275 223H298M286 210V236M703 179H725M714 168V190','none','stroke="#C4B4FF" stroke-width="5"');headwear.append(('Moonlight Halo',1,s))
headwear.append(('None',14,''))

accessories=[]
s='<g class="line">'+path('M348 760Q498 931 654 760','none','stroke="#795125" stroke-width="24"')+path('M348 760Q498 931 654 760','none','stroke="#FFC46B" stroke-width="13" stroke-dasharray="12 11"')+rect(421,824,158,60,'#FFC46B','rx="11" stroke-width="8"')+text(500,866,'$SHIFT',29,'#5B371B','text-anchor="middle"')+'</g>';accessories.append(('SHIFT Chain',15,s))
# The badge number is appended by the renderer at the same anchor, never a static stand-in.
s='<g class="line">'+path('M386 751L494 833L591 749','none','stroke="#7C5CFF" stroke-width="16"')+rect(430,805,143,83,'#E6E5DF','rx="8" stroke-width="6"')+rect(430,805,143,28,'#1E2236','rx="5" stroke="none"')+text(500,825,'NIGHT CREW',14,'#F2EFFF','text-anchor="middle"')+path('M443 873H463M468 873H484M489 873H508M513 873H527M532 873H557','none','stroke-width="6"')+'</g>';accessories.append(('Crew ID Badge',22,s))
s='<g class="line">'+path('M752 770Q840 761 825 826Q816 850 780 846','none','stroke="#08070D" stroke-width="27"')+path('M752 770Q840 761 825 826Q816 850 780 846','none','stroke="#C4B4FF" stroke-width="13"')+path('M646 744H777L765 874Q707 903 655 873Z','#C4B4FF')+'<ellipse cx="711" cy="747" rx="65" ry="15" fill="#3A231F" stroke-width="8"/>'+text(711,813,'SHIP',24,INK,'text-anchor="middle"')+text(711,844,'IT.',26,INK,'text-anchor="middle"')+path('M672 710Q646 686 671 659M715 708Q691 677 720 646M750 707Q733 683 755 661','none','stroke="#E5E0F1" stroke-width="7" opacity=".6"')+'</g>';accessories.append(('Shipping Coffee',27,s))
s='<g class="line">'+rect(676,725,100,164,'#141625','rx="16"')+rect(681,734,90,20,'#A2AAB5','rx="6" stroke-width="5"')+path('M728 760L696 813H725L707 862L757 794H727Z',ACID,'stroke-width="5"')+path('M688 767V865','none','stroke="#3FE6FF" stroke-width="5"')+'</g>';accessories.append(('Overtime Energy',14,s))
s='<g class="line">'+path('M748 492Q806 501 789 559Q779 585 754 573','none','stroke="#151D2E" stroke-width="24"')+circle(766,525,33,'#2A2354','stroke-width="8"')+path('M749 525L766 507L782 525L766 543Z','#7C5CFF','stroke="#3FE6FF" stroke-width="3"')+circle(766,525,6,'#F2EFFF','stroke="none"')+path('M789 508Q812 521 801 544','none','stroke="#3FE6FF" stroke-width="4"')+'</g>';accessories.append(('IMD Swarm Earpiece',8,s))
accessories.append(('None',14,''))

traits=[backgrounds,bodies,skins,mouths,eyes,headwear,accessories]
names=['Background','Body','Skin','Mouth','Eyes','Headwear','Accessory']
# Store names and fragments next to one another. Global offsets used by renderer.
records=[base_style+defs,finish,placeholder,unique]
manifest=[]
for category,group in zip(names,traits):
    entries=[]
    for i,item in enumerate(group):
        name,weight,svg,*accent=item
        record=len(records)
        records.extend([name,svg])
        entries.append({'index':i,'name':name,'weight':weight,'nameRecord':record,'svgRecord':record+1,**({'accent':accent[0]} if accent else {})})
        d=ART/category.lower(); d.mkdir(exist_ok=True)
        (d/f'{i:02d}.svg').write_text(svg+'\n')
    manifest.append({'category':category,'traits':entries})
(ART/'catalog.json').write_text(json.dumps(manifest,indent=2)+'\n')
(ART/'common.svg').write_text(base_style+defs+'\n')
(ART/'finish.svg').write_text(finish+'\n')
(ART/'placeholder.svg').write_text(placeholder+'\n')
(ART/'captain.svg').write_text(unique+'\n')

# Greedy pack into three bytecode payloads below EIP-170. Every record remains whole.
banks=[]; current=[]; length=0
for value in records:
    n=len(value.encode())+2
    if length+n+4>24000:
        banks.append(current);current=[];length=0
    current.append(value);length+=n
banks.append(current)
assert len(banks)<=4, (len(banks), sum(len(s) for s in records))
index=0;bankinfo=[]
for i,bank in enumerate(banks):
    header=2+2*(len(bank)+1)
    offsets=[header]
    data=b''
    for item in bank:
        data+=item.encode(); offsets.append(header+len(data))
    packed=len(bank).to_bytes(2,'big')+b''.join(o.to_bytes(2,'big') for o in offsets)+data
    name=f'FrogArt{i+1}'
    # Hex literals avoid Solidity string escaping and retain the exact SVG bytes.
    chunks='\n'.join('            hex"'+packed.hex()[j:j+200]+'"' for j in range(0,len(packed)*2,200))
    source='// SPDX-License-Identifier: MIT\npragma solidity 0.8.26;\n\nimport {ArtStore} from "./ArtStore.sol";\n\n'
    source+='/// @dev Generated by tools/build_art.py. Original SVG master records in art/.\n'
    source+=f'contract {name} is ArtStore {{\n    constructor()\n        ArtStore(\n{chunks},\n            {len(bank)}\n        )\n    {{}}\n}}\n'
    (OUT/f'{name}.sol').write_text(source)
    bankinfo.append({'contract':name,'start':index,'count':len(bank),'bytes':len(packed)})
    print(name,'records',index,'to',index+len(bank)-1,'payload',len(packed),'bytes')
    index+=len(bank)
(ART/'banks.json').write_text(json.dumps(bankinfo,indent=2)+'\n')
print('Total records',len(records),'Total bytes',sum(len(s.encode()) for s in records))
