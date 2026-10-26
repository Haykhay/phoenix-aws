"""Generates docs/architecture/phoenix-networking.drawio (Phoenix networking, Layer 1).

Same helpers and style as infrastructure/docs/architecture/gen_diagram.py:
AWS 2024 icons (mxgraph.aws4); brand marks embedded from icons/.

usage: python3 gen_diagram.py   (then export with the draw.io CLI, see README)
"""
import base64
import pathlib
from xml.sax.saxutils import escape

HERE = pathlib.Path(__file__).resolve().parent
cells = []
_id = [1]


def nid():
    _id[0] += 1
    return f"c{_id[0]}"


def q(text):
    return escape(text, {'"': "&quot;"})


def vertex(label, x, y, w, h, style):
    i = nid()
    cells.append(f'<mxCell id="{i}" value="{q(label)}" style="{style}" vertex="1" parent="1">'
                 f'<mxGeometry x="{x}" y="{y}" width="{w}" height="{h}" as="geometry"/></mxCell>')
    return i


def edge(src, dst, label="", dashed=False, exit_=None, entry=None, points=()):
    i = nid()
    s = ("edgeStyle=orthogonalEdgeStyle;rounded=1;html=1;endArrow=block;endFill=1;strokeWidth=2;"
         "strokeColor=#232F3E;fontSize=12;fontColor=#232F3E;labelBackgroundColor=#FFFFFF;")
    if dashed:
        s += "dashed=1;strokeColor=#545B64;"
    if exit_:
        s += f"exitX={exit_[0]};exitY={exit_[1]};exitDx=0;exitDy=0;"
    if entry:
        s += f"entryX={entry[0]};entryY={entry[1]};entryDx=0;entryDy=0;"
    pts = "".join(f'<mxPoint x="{x}" y="{y}"/>' for x, y in points)
    geo = f'<mxGeometry relative="1" as="geometry">{"<Array as=" + chr(34) + "points" + chr(34) + ">" + pts + "</Array>" if pts else ""}</mxGeometry>'
    cells.append(f'<mxCell id="{i}" value="{q(label)}" style="{s}" edge="1" parent="1" source="{src}" target="{dst}">{geo}</mxCell>')
    return i


LABEL = ("verticalLabelPosition=bottom;verticalAlign=top;align=center;html=1;fontSize=12;"
         "fontColor=#232F3E;aspect=fixed;")
ICON = "sketch=0;outlineConnect=0;dashed=0;fontStyle=0;" + LABEL

# AWS 2024 category colours
COMPUTE, STORAGE, DB, NET, SEC, MGMT, ANALYTICS, INTEG = (
    "#ED7100", "#7AA116", "#C925D1", "#8C4FFF", "#DD344C", "#E7157B", "#8C4FFF", "#E7157B")


def svc(label, x, y, icon, color, size=56):
    """AWS service icon."""
    return vertex(label, x, y, size, size,
                  ICON + f"strokeColor=#ffffff;fillColor={color};shape=mxgraph.aws4.resourceIcon;resIcon=mxgraph.aws4.{icon};")


def res(label, x, y, shape, color, size=56):
    """AWS resource-level icon (NAT gateway, hosted zone, role, ...)."""
    return vertex(label, x, y, size, size,
                  ICON + f"strokeColor=none;fillColor={color};pointerEvents=1;shape=mxgraph.aws4.{shape};")


def brand(label, x, y, name, size=40, tile=None):
    """Embedded brand mark from icons/<name>.svg, optionally on a coloured tile."""
    if tile:
        vertex("", x - 6, y - 6, size + 12, size + 12,
               f"rounded=1;arcSize=18;fillColor={tile};strokeColor=none;")
    path = next((HERE / "icons").glob(f"{name}.*"))
    mime = "image/svg+xml" if path.suffix == ".svg" else "image/png"
    data = base64.b64encode(path.read_bytes()).decode()
    return vertex(label, x, y, size, size,
                  LABEL + f"shape=image;imageAspect=0;image=data:{mime},{data};" +
                  ("spacingTop=8;" if tile else ""))


def group(label, x, y, w, h, gr_icon, stroke, fill="none", font=None, dashed=0, extra=""):
    return vertex(label, x, y, w, h,
                  "points=[];outlineConnect=0;html=1;whiteSpace=wrap;fontSize=13;fontStyle=1;"
                  f"shape=mxgraph.aws4.group;grIcon=mxgraph.aws4.{gr_icon};strokeColor={stroke};fillColor={fill};"
                  f"verticalAlign=top;align=left;spacingLeft=30;fontColor={font or stroke};dashed={dashed};{extra}")


def box(label, x, y, w, h, fill="#FFFFFF", stroke="#232F3E", extra=""):
    return vertex(label, x, y, w, h,
                  f"rounded=1;whiteSpace=wrap;html=1;arcSize=4;fillColor={fill};strokeColor={stroke};"
                  f"fontColor=#232F3E;fontSize=12;align=left;verticalAlign=top;spacingLeft=10;spacingTop=6;{extra}")


def text(label, x, y, w, h, size=11, color="#545B64", bold=False):
    return vertex(label, x, y, w, h,
                  f"text;html=1;whiteSpace=wrap;fontSize={size};fontColor={color};align=left;verticalAlign=top;"
                  f"{'fontStyle=1;' if bold else ''}")


PROD, NONPROD, SHARED = "#D13212", "#1F7A3E", "#8C4FFF"


def tables(x, y):
    """The three route tables every transit gateway has."""
    box("<b>production</b>", x, y, 150, 30, fill="#FDECEA", stroke=PROD, extra="spacingTop=2;align=center;")
    box("<b>non-production</b>", x, y + 38, 150, 30, fill="#E9F5EC", stroke=NONPROD, extra="spacingTop=2;align=center;")
    box("<b>shared</b>", x, y + 76, 150, 30, fill="#F3EDFF", stroke=SHARED, extra="spacingTop=2;align=center;")


def tgw(label, x, y):
    return res(label, x, y, "transit_gateway", NET, 64)


# ===================================================================== header
vertex("<b>Phoenix networking on AWS — hub and spoke, on demand</b><br><span style='font-size:13px'>"
       "a region's transit gateway is created with its first environment · production and non-production never meet · "
       "the tooling VPC reaches both</span>",
       40, 20, 2000, 56, "text;html=1;fontSize=24;fontColor=#232F3E;align=left;verticalAlign=top;")

# ===================================================================== Backstage  (x 40..420)
BX, BW = 40, 400
box("", BX, 110, BW, 640, fill="#F1F5FB", stroke="#1F5FBF")
brand("", BX + 20, 126, "backstage", 30, tile="#121212")
text("Backstage", BX + 66, 128, 300, 24, size=15, color="#1F5FBF", bold=True)
settings = box("<b>platform.yaml</b> — the adopter decides once<br>hub region(s) · address space · segment / region / VPC sizes<br>"
               "egress mode: central | independent<br>hybrid: none | vpn | dx_vpn | dual_dx<br>on-prem CIDRs · DNS forwarding · share with",
               BX + 20, 176, BW - 40, 110)
form = box("<b>Environment form</b><br>the requester picks a region and a tier — never networking",
           BX + 20, 304, BW - 40, 56)
check = box("<b>Region has a network?</b> (phoenix-region entity)<br>no → write networking units first:<br>"
            "① ipam.yaml (+ region) → ② region.yaml →<br>③ peering.&lt;peer&gt;.yaml for every region → ④ entity",
            BX + 20, 378, BW - 40, 96, fill="#FFF8E7", stroke="#B07A00")
env = box("<b>Then the environment, as today</b><br>core-network (attach, segment from tier) → core-platform → …",
          BX + 20, 492, BW - 40, 56)
brand("", BX + 26, 572, "githubactions", 26)
gha = box("<b>GitHub Actions</b> — one workflow, networking/ added<br>networking units run on GitHub-hosted runners",
          BX + 64, 566, BW - 84, 56, stroke="#24292F")
text("Requesters see none of this: a missing region is built first, then their request carries on.", BX + 20, 640, BW - 40, 60)

# ===================================================================== tooling account  (x 40..420)
group("Tooling account", BX, 790, BW, 330, "group_account", "#E7157B")
group("Tooling VPC · hub region · shared segment", BX + 20, 830, BW - 40, 270, "group_vpc2", "#8C4FFF")
brand("", BX + 50, 880, "backstage", 34, tile="#121212")
text("Backstage", BX + 100, 888, 120, 24)
runner = box("<b>phoenix-mgmt runner</b><br>reaches every cluster's private<br>EKS API, in every region",
             BX + 40, 940, 300, 66, stroke="#24292F")
tool_att = res("attachment<br>→ shared", BX + 300, 1030, "transit_gateway_attachment", NET, 44)

# ===================================================================== networking account
NX, NW = 480, 1540
group("Networking account — owns every transit gateway, IPAM, egress, hybrid, DNS", NX, 110, NW, 1000,
      "group_account", "#E7157B")

# IPAM
ipam_box = box("<b>IPAM</b> (delegated admin) — one summary route per segment<br>"
               "address space, default 10.0.0.0/8 · VPCs: sandbox /20, others /18<br>"
               "├ <font color='#D13212'><b>production</b></font> 10.0.0.0/10 → one /13 per region, on demand<br>"
               "├ <font color='#1F7A3E'><b>non-production</b></font> 10.64.0.0/10 → one /13 per region<br>"
               "├ <font color='#8C4FFF'><b>shared</b></font> 10.128.0.0/10 → tooling · hub DNS · egress VPCs<br>"
               "└ reserved",
               NX + 30, 150, 700, 140)
svc("", NX + 650, 160, "vpc", NET, 48)

# hub region
HX, HY = NX + 30, 320
group("Hub region (platform setting) — always exists", HX, HY, 700, 540, "group_region", "#00A4A6", dashed=1)
hub_tgw = tgw("hub transit gateway", HX + 270, HY + 70)
tables(HX + 380, HY + 50)
egress_h = group("Egress VPC (central mode)", HX + 20, HY + 230, 250, 140, "group_vpc2", "#8C4FFF", dashed=1)
res("NAT", HX + 50, HY + 280, "nat_gateway", NET, 44)
res("IGW", HX + 150, HY + 280, "internet_gateway", NET, 44)
dns = group("Hub DNS VPC (hybrid / forwarding)", HX + 390, HY + 230, 290, 140, "group_vpc2", "#8C4FFF", dashed=1)
svc("Resolver<br>inbound · outbound", HX + 420, HY + 272, "route_53", NET, 48)
text("forwarding rules shared by RAM<br>env internal zones associated", HX + 510, HY + 280, 160, 60)
vpn = res("Site-to-site VPN<br>2 IPsec tunnels", HX + 42, HY + 420, "vpn_connection", NET, 48)
dxgw = svc("Direct Connect gateway", HX + 190, HY + 420, "direct_connect", NET, 48)
text("hybrid: vpn · dx_vpn · dual_dx<br>attached in <b>shared</b>; BGP<br>propagates on-prem routes", HX + 420, HY + 420, 260, 60)

# second hub

# regions on demand
RX = NX + 780
group("Region B — created with its first environment", RX, 150, 730, 430, "group_region", "#00A4A6", dashed=1)
b_tgw = tgw("regional<br>transit gateway", RX + 280, 210)
tables(RX + 390, 262)
group("Egress VPC (central mode)", RX + 30, 360, 300, 140, "group_vpc2", "#8C4FFF", dashed=1)
res("NAT", RX + 60, 410, "nat_gateway", NET, 44)
res("IGW", RX + 160, 410, "internet_gateway", NET, 44)
text("+ 3 regional IPAM pools<br>never removed automatically", RX + 400, 400, 300, 50)

group("Region C — the next one, on demand", RX, 610, 730, 250, "group_region", "#00A4A6", dashed=1)
c_tgw = tgw("regional<br>transit gateway", RX + 280, 660)
tables(RX + 390, 640)
text("peers with both hubs and every region already there (full mesh)", RX + 30, 790, 680, 30)

H2Y = 890
group("Second hub region (only with dual_dx)", RX, H2Y, 730, 200, "group_region", "#00A4A6", dashed=1)
hub2_tgw = tgw("second hub<br>transit gateway", RX + 280, H2Y + 50)
tables(RX + 390, H2Y + 40)
text("same Direct Connect gateway, second connection<br>peers with every transit gateway, like the hub", RX + 30, H2Y + 150, 680, 40)

# routing rules
box("<b>On every transit gateway</b><br>"
    "<font color='#D13212'><b>production</b></font>: prod VPCs · learns prod + tooling · <b>blackhole</b> non-production · (central) 0/0 → egress<br>"
    "<font color='#1F7A3E'><b>non-production</b></font>: sandbox · stage · uat · <b>blackhole</b> production · (central) 0/0 → egress<br>"
    "<font color='#8C4FFF'><b>shared</b></font>: tooling, DNS, egress, on-prem, peerings · reaches everything<br>"
    "peering: static routes per segment block, both sides",
    RX, 1160, 730, 130, fill="#FAFAFA", stroke="#545B64")

# ===================================================================== group accounts  (x 2060..2560)
GX, GW = 2060, 500
group("Group account — production", GX, 110, GW, 360, "group_account", "#E7157B")
group("prod VPC · region B · production segment", GX + 20, 150, GW - 40, 300, "group_vpc2", PROD)
prod_eks = svc("EKS + Cilium", GX + 60, 210, "eks", COMPUTE, 56)
res("NAT (independent<br>mode only)", GX + 260, 210, "nat_gateway", NET, 44)
prod_att = res("attachment<br>→ production", GX + 60, 340, "transit_gateway_attachment", NET, 44)

group("Group account — non-production", GX, 500, GW, 360, "group_account", "#E7157B")
group("sandbox VPC · region B · non-production segment", GX + 20, 540, GW - 40, 300, "group_vpc2", NONPROD)
np_eks = svc("EKS + Cilium", GX + 60, 600, "eks", COMPUTE, 56)
res("NAT (independent<br>mode only)", GX + 260, 600, "nat_gateway", NET, 44)
np_att = res("attachment<br>→ non-production", GX + 60, 730, "transit_gateway_attachment", NET, 44)

box("<b>Cilium</b> (k8s-installs baseline, chained with the VPC CNI)<br>default: own VPC · tooling · DNS · Pod Identity · internet<br>"
    "everything else private is denied until a policy opens it<br>(spec.egress_allow · team CiliumNetworkPolicies, FQDN rules)",
    GX, 880, GW, 110, fill="#FFFFFF", stroke="#545B64")
text("Teams are not separated by AWS routing: within a segment any VPC can route to any other; Cilium decides.",
     GX, 1000, GW, 60)

# ===================================================================== on-prem
group("Corporate data centre — the adopter's (optional)", NX, 1160, 700, 200, "group_corporate_data_center", "#5A6C86")
onprem = box("<b>Edge device + firewall</b><br>decides what on-prem reaches in each segment", NX + 30, 1210, 330, 60, stroke="#5A6C86")
box("<b>DNS servers</b><br>forward AWS zones → Resolver inbound", NX + 380, 1210, 290, 60, stroke="#5A6C86")
text("on-prem CIDRs must not overlap the address space · AWS advertises the three segment summaries",
     NX + 30, 1290, 640, 40)

box("<b>Egress modes</b> (platform setting)<br><b>central</b>: env VPCs have no NAT; 0/0 → transit gateway → region's egress VPC<br>"
    "<b>independent</b>: each VPC its own NAT; no default route on the transit gateway<br>"
    "either way, inbound load balancers use the VPC's own IGW",
    GX, 1100, GW, 110, fill="#FFFFFF", stroke="#545B64")

# ===================================================================== flows
edge(form, check, "", exit_=(0.5, 1), entry=(0.5, 0))
edge(check, env, "", exit_=(0.5, 1), entry=(0.5, 0))
edge(env, gha, "", exit_=(0.5, 1), entry=(0.5, 0))
edge(gha, ipam_box, "① ② ③ apply", exit_=(1, 0.5), entry=(0, 0.5), points=[(460, 594), (460, 220)])
edge(tool_att, hub_tgw, "shared", exit_=(1, 0.5), entry=(0, 0.5), points=[(470, 1052), (470, 422)])
edge(hub_tgw, b_tgw, "peering", exit_=(1, 0.2), entry=(0, 0.5),
     points=[(HX + 355, HY + 83), (HX + 355, 305), (RX - 40, 305), (RX - 40, 242)])
edge(hub_tgw, c_tgw, "peering", exit_=(1, 0.8), entry=(0, 0.5),
     points=[(HX + 355, HY + 121), (HX + 355, 868), (RX - 25, 868), (RX - 25, 692)])
edge(b_tgw, c_tgw, "peering", exit_=(0.5, 1), entry=(0.5, 0))
edge(hub_tgw, hub2_tgw, "peering", dashed=True, exit_=(0.5, 1), entry=(0, 0.5),
     points=[(HX + 302, 884), (RX - 40, 884), (RX - 40, H2Y + 82)])
edge(c_tgw, hub2_tgw, "peering", dashed=True, exit_=(0.5, 1), entry=(0.5, 0))
edge(prod_att, b_tgw, "", exit_=(0, 0.5), entry=(1, 0.15), points=[(GX - 20, 362), (GX - 20, 220)])
edge(np_att, b_tgw, "", exit_=(0, 0.5), entry=(1, 0.5), points=[(GX - 40, 752), (GX - 40, 242)])
edge(onprem, vpn, "IPsec", exit_=(0.2, 0), entry=(0.5, 1))
edge(onprem, dxgw, "Direct Connect", exit_=(0.8, 0), entry=(0.5, 1), points=[(NX + 294, 1140), (HX + 214, 1140)])

xml = ('<mxfile host="drawio"><diagram id="networking" name="Phoenix networking">'
       '<mxGraphModel dx="2600" dy="1400" grid="0" gridSize="10" guides="1" tooltips="1" connect="1" arrows="1" '
       'fold="1" page="0" pageScale="1" pageWidth="2600" pageHeight="1400" math="0" shadow="0" background="#FFFFFF">'
       '<root><mxCell id="0"/><mxCell id="1" parent="0"/>' + "".join(cells) +
       '</root></mxGraphModel></diagram></mxfile>')
(HERE / "phoenix-networking.drawio").write_text(xml)
print("wrote", HERE / "phoenix-networking.drawio", len(cells), "cells")
