import streamlit as st

CSS = """
@import url('https://fonts.googleapis.com/css2?family=Source+Sans+3:wght@400;600;700&family=JetBrains+Mono:wght@400;700&display=swap');
html, body, .stApp {font-family: 'Source Sans 3', sans-serif;}
.stApp {background: linear-gradient(135deg, #eef8f4 0%, #ffffff 45%, #ecf8f2 100%);}
header[data-testid="stHeader"] {background: transparent;}
#MainMenu, footer {visibility: hidden;}
.block-container {max-width: 1150px; padding-top: 1.5rem;}
.mono {font-family: 'JetBrains Mono', monospace; text-transform: uppercase;}
.brand {display: flex; align-items: center; justify-content: space-between; margin-bottom: 6px;}
.brand-left {display: flex; align-items: center; gap: 14px;}
.logo {width: 46px; height: 46px; border-radius: 13px; background: linear-gradient(135deg, #064e3b, #10b981); display: flex; align-items: center; justify-content: center; font-size: 22px;}
.brand-name {font-size: 1.6rem; font-weight: 700; color: #064e3b; line-height: 1.1;}
.brand-sub {font-family: 'JetBrains Mono', monospace; font-size: .72rem; letter-spacing: .22em; color: #4b6b60;}
.status {font-family: 'JetBrains Mono', monospace; font-size: .72rem; letter-spacing: .15em; color: #059669; font-weight: 700;}
.status::before {content: ""; display: inline-block; width: 9px; height: 9px; border-radius: 50%; background: #10b981; margin-right: 8px;}
.hero {position: relative; overflow: hidden; background: linear-gradient(135deg, #064e3b 0%, #047857 65%, #059669 100%); border-radius: 26px; padding: 34px 32px; margin: 18px 0 20px; box-shadow: 0 18px 40px rgba(6, 78, 59, .25);}
.hero::after {content: ""; position: absolute; right: -90px; top: -120px; width: 420px; height: 420px; border-radius: 50%; background: rgba(255, 255, 255, .07);}
.pill {display: inline-block; font-family: 'JetBrains Mono', monospace; font-size: .72rem; letter-spacing: .2em; font-weight: 700; color: #fff; padding: 6px 16px; border-radius: 999px; border: 1px solid rgba(255, 255, 255, .35); background: rgba(255, 255, 255, .12);}
.hero h1 {color: #fff; font-size: 2.6rem; font-weight: 700; line-height: 1.1; margin: 18px 0 12px; padding: 0;}
.hero p {color: #d1fae5; font-size: 1.05rem; max-width: 760px; line-height: 1.5; margin: 0;}
.byline {font-family: 'JetBrains Mono', monospace; font-size: .75rem; letter-spacing: .15em; color: #a7f3d0; margin-top: 16px;}
.grid2 {display: grid; grid-template-columns: 1fr 1fr; gap: 16px; margin-bottom: 10px;}
.metric {background: rgba(255, 255, 255, .75); border: 1px solid #d1fae5; border-left: 5px solid #10b981; border-radius: 18px; padding: 16px 22px;}
.metric .label {font-family: 'JetBrains Mono', monospace; font-size: .72rem; letter-spacing: .18em; color: #4b6b60;}
.metric .value {font-size: 2rem; font-weight: 700; color: #059669; line-height: 1.2;}
.metric .sub {color: #4b5b55; font-size: .9rem;}
.section {display: flex; align-items: center; gap: 12px; margin: 34px 0 14px; font-family: 'JetBrains Mono', monospace; font-size: .9rem; letter-spacing: .2em; font-weight: 700; color: #064e3b;}
.section::before {content: ""; width: 11px; height: 11px; background: #10b981; transform: rotate(45deg);}
.section::after {content: ""; flex: 1; height: 1px; background: linear-gradient(90deg, #10b981, rgba(16, 185, 129, 0));}
.step {display: flex; gap: 16px; align-items: flex-start; background: rgba(255, 255, 255, .75); border: 1px solid #d1fae5; border-radius: 18px; padding: 18px 22px; margin-bottom: 12px;}
.step .num {flex: none; width: 40px; height: 40px; border-radius: 11px; background: linear-gradient(135deg, #047857, #10b981); color: #fff; font-weight: 700; display: flex; align-items: center; justify-content: center;}
.step .title {font-weight: 700; color: #064e3b; font-size: 1.1rem;}
.step .text {color: #4b5b55;}
div[class*="st-key-card"] {background: rgba(255, 255, 255, .7); border: 1px solid #d1fae5; border-radius: 22px; padding: 18px 22px;}
@media (max-width: 700px) {.grid2 {grid-template-columns: 1fr;} .hero h1 {font-size: 1.8rem;}}
"""


def html(markup):
    # markdown breaks on indented or blank lines, so flatten the html first
    flat = "\n".join(line.strip() for line in markup.splitlines() if line.strip())
    st.markdown(flat, unsafe_allow_html=True)


def inject_css():
    html("<style>" + CSS + "</style>")


def header(status):
    html(f"""
    <div class="brand">
      <div class="brand-left">
        <div class="logo">🏠</div>
        <div><div class="brand-name">PakProp Index</div><div class="brand-sub">PRICE TRENDS</div></div>
      </div>
      <div class="status">{status}</div>
    </div>""")


def hero(tag, title, text, byline):
    html(f"""
    <div class="hero">
      <span class="pill">{tag}</span>
      <h1>{title}</h1>
      <p>{text}</p>
      <div class="byline">{byline}</div>
    </div>""")


def metric_cards(items):
    cards = "".join(
        f'<div class="metric"><div class="label">{label}</div><div class="value">{value}</div><div class="sub">{sub}</div></div>'
        for label, value, sub in items)
    html(f'<div class="grid2">{cards}</div>')


def section(title):
    html(f'<div class="section">{title}</div>')


def steps(items):
    for number, (title, text) in enumerate(items, start=1):
        html(f'<div class="step"><div class="num">{number}</div><div><div class="title">{title}</div><div class="text">{text}</div></div></div>')


def style_fig(fig):
    fig.update_layout(
        template="plotly_white",
        paper_bgcolor="rgba(0,0,0,0)",
        plot_bgcolor="rgba(0,0,0,0)",
        font=dict(family="Source Sans 3, sans-serif", color="#1f3d33"),
        margin=dict(l=10, r=10, t=30, b=10),
        legend_title_text="",
        xaxis=dict(gridcolor="#e3f3ec"),
        yaxis=dict(gridcolor="#e3f3ec"),
    )
    return fig


def show(fig, fmt=",.1f", prefix="", suffix="", date=False):
    # one tooltip for the whole x position, every series listed as "name: value"
    fig.update_traces(hovertemplate=f"%{{fullData.name}}: <b>{prefix}%{{y:{fmt}}}{suffix}</b><extra></extra>")
    fig.update_layout(
        hovermode="x unified",
        hoverlabel=dict(bgcolor="white", bordercolor="#10b981",
                        font=dict(family="Source Sans 3, sans-serif", size=13, color="#1f3d33")),
    )
    fig.update_xaxes(showspikes=True, spikemode="across", spikethickness=1,
                     spikecolor="#10b981", spikedash="dot")
    if date:
        fig.update_xaxes(hoverformat="%b %Y")
    st.plotly_chart(style_fig(fig), use_container_width=True, theme=None)
