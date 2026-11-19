# Genera el AppIcon de Aura. Uso: python3 scripts/generate_icon.py Aura/Resources/Assets.xcassets/AppIcon.appiconset [preview.png]
# Requiere Pillow solo para regenerar: los PNG ya están en el repo.
from PIL import Image, ImageDraw, ImageFilter, ImageChops
import math, sys, json, os
S=2048; k=S/1024
def lerp(a,b,t): return tuple(int(a[i]+(b[i]-a[i])*t) for i in range(len(a)))
# background gradient
bg=Image.new("RGBA",(S,S))
top=(18,32,74,255); bot=(4,7,20,255)
d=ImageDraw.Draw(bg)
for y in range(S): d.line([(0,y),(S,y)],fill=lerp(top,bot,y/S))
# radial glow
glow=Image.new("RGBA",(S,S),(0,0,0,0)); g=ImageDraw.Draw(glow)
cx,cy=S/2,S*0.58
for r in range(int(420*k),0,-8):
    a=int(110*(1-r/(420*k))**1.6)
    g.ellipse([cx-r,cy-r,cx+r,cy+r],fill=(47,120,255,a))
bg=Image.alpha_composite(bg,glow)
# rings (aura waves)
rings=Image.new("RGBA",(S,S),(0,0,0,0)); rd=ImageDraw.Draw(rings)
for i,(r,w,a) in enumerate([(250,24,235),(320,19,150),(390,14,80)]):
    r*=k; w=int(w*k)
    rd.arc([cx-r,cy-r,cx+r,cy+r],start=215,end=325,fill=(110,190,255,a),width=w)
rings=rings.filter(ImageFilter.GaussianBlur(1.5*k))
ringglow=rings.filter(ImageFilter.GaussianBlur(18*k))
bg=Image.alpha_composite(bg,ringglow); bg=Image.alpha_composite(bg,rings)
# core orb with gradient
orb=Image.new("RGBA",(S,S),(0,0,0,0)); od=ImageDraw.Draw(orb)
R=int(140*k)
for r in range(R,0,-2):
    t=r/R
    od.ellipse([cx-r,cy-r-(1-t)*40*k,cx+r,cy+r-(1-t)*40*k],fill=lerp((200,235,255,255),(40,100,255,255),t**0.8))
og=orb.filter(ImageFilter.GaussianBlur(60*k)); bg=Image.alpha_composite(bg,og); bg=Image.alpha_composite(bg,orb)
# squircle mask (macOS grid: 824 inside 1024)
m=Image.new("L",(S,S),0); md=ImageDraw.Draw(m)
x0=100*k; x1=924*k
md.rounded_rectangle([x0,x0,x1,x1],radius=int(185*k),fill=255)
# inner top highlight border
hl=Image.new("RGBA",(S,S),(0,0,0,0)); hd=ImageDraw.Draw(hl)
hd.rounded_rectangle([x0,x0,x1,x1],radius=int(185*k),outline=(255,255,255,40),width=int(3*k))
bg=Image.alpha_composite(bg,hl)
out=Image.new("RGBA",(S,S),(0,0,0,0)); out.paste(bg,(0,0),m)
# drop shadow
sh=Image.new("RGBA",(S,S),(0,0,0,0)); sm=m.filter(ImageFilter.GaussianBlur(14*k))
sh.paste((0,0,0,110),(0,int(10*k)),sm)
final=Image.alpha_composite(sh,out).resize((1024,1024),Image.LANCZOS)
dest=sys.argv[1]; os.makedirs(dest,exist_ok=True)
imgs=[]
for size in [16,32,128,256,512]:
    for sc in [1,2]:
        px=size*sc; fn=f"icon_{size}x{size}{'@2x' if sc==2 else ''}.png"
        final.resize((px,px),Image.LANCZOS).save(os.path.join(dest,fn))
        imgs.append({"idiom":"mac","scale":f"{sc}x","size":f"{size}x{size}","filename":fn})
json.dump({"images":imgs,"info":{"author":"xcode","version":1}},open(os.path.join(dest,"Contents.json"),"w"),indent=2)
if len(sys.argv) > 2: final.save(sys.argv[2])  # vista previa opcional
