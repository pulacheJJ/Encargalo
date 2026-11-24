"""Recursos dibujados por código e informe PDF; no fabrica capturas de la app."""
from pathlib import Path
from PIL import Image, ImageDraw

ROOT = Path(__file__).resolve().parent.parent
DOCUMENTATION = ROOT.parent/'encargalo_documentacion'

def icons():
    for density, size in [('mdpi',48),('hdpi',72),('xhdpi',96),('xxhdpi',144),('xxxhdpi',192)]:
        im = Image.new('RGB',(size,size),'#6D28D9')
        d = ImageDraw.Draw(im)
        k = size/100
        d.rounded_rectangle((23*k,33*k,77*k,82*k),radius=8*k,fill='white')
        d.arc((35*k,17*k,65*k,48*k),180,360,fill='white',width=max(2,round(5*k)))
        d.line([(37*k,55*k),(47*k,65*k),(65*k,46*k)],fill='#6D28D9',width=max(2,round(5*k)))
        p = ROOT/'android/app/src/main/res'/f'mipmap-{density}'/'ic_launcher.png'
        p.parent.mkdir(parents=True,exist_ok=True)
        im.save(p)
    print('Iconos PNG generados sin recursos remotos.')

def report():
    from reportlab.platypus import SimpleDocTemplate, Paragraph, Spacer, Preformatted
    from reportlab.lib.styles import getSampleStyleSheet
    from reportlab.lib import colors
    from reportlab.lib.enums import TA_LEFT
    from reportlab.pdfbase import pdfmetrics
    from reportlab.pdfbase.ttfonts import TTFont
    from xml.sax.saxutils import escape
    target=DOCUMENTATION/'INFORME_TECNICO.pdf'
    target.parent.mkdir(exist_ok=True)
    styles=getSampleStyleSheet()
    font=Path('C:/Windows/Fonts/arial.ttf')
    bold=Path('C:/Windows/Fonts/arialbd.ttf')
    if font.exists() and bold.exists():
        pdfmetrics.registerFont(TTFont('EncargaloSans',str(font)))
        pdfmetrics.registerFont(TTFont('EncargaloSansBold',str(bold)))
        for name in ['Normal','BodyText','Title','Heading2','Heading3']:
            styles[name].fontName='EncargaloSansBold' if name in ['Title','Heading2','Heading3'] else 'EncargaloSans'
    styles['Title'].textColor=colors.HexColor('#6D28D9')
    for name in ['Normal','BodyText']:
        styles[name].leading=15
        styles[name].alignment=TA_LEFT
    flow=[]
    for filename in ['INFORME_TECNICO.md','REVISION_1_1_0.md','RESULTADOS.md','MATRIZ_SEMANAL.md']:
        source=DOCUMENTATION/filename
        if not source.exists(): continue
        for line in source.read_text(encoding='utf-8').splitlines():
            if not line.strip(): flow.append(Spacer(1,6)); continue
            style='Title' if line.startswith('# ') else 'Heading2' if line.startswith('## ') else 'Heading3' if line.startswith('### ') else 'BodyText'
            text=escape(line.lstrip('# ').replace('**','').replace('`',''))
            flow.append(Paragraph(text,styles[style]))
    def footer(canvas,doc):
        canvas.setFont('Helvetica',8)
        canvas.drawString(40,25,'Encargalo - Informe de implementacion; el estado cloud figura expresamente en Resultados.')
        canvas.drawRightString(555,25,str(doc.page))
    SimpleDocTemplate(str(target),rightMargin=40,leftMargin=40,topMargin=40,bottomMargin=45,title='Encargalo - Informe tecnico').build(flow,onFirstPage=footer,onLaterPages=footer)
    print('PDF generado:',target)

if __name__=='__main__':
    icons()
    report()
