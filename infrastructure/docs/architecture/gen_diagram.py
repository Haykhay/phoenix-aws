"""Generates docs/architecture/phoenix-architecture.drawio.

AWS resources use draw.io's AWS 2024 icon set (mxgraph.aws4). Brands draw.io
does not ship are embedded from icons/: official marks from Simple Icons
(Backstage, Terraform, GitHub, GitHub Actions, Grafana, Prometheus, NVIDIA,
OpenTelemetry), Langfuse's own SVG (langfuse.com) and vLLM's own PNG
(github.com/vllm-project/vllm).

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


# ===================================================================== header
vertex("<b>Phoenix — self-service AWS environments</b><br><span style='font-size:13px'>"
       "Backstage takes the request · GitHub holds the YAML and runs Terraform · one AWS account per group</span>",
       40, 20, 1500, 56, "text;html=1;fontSize=24;fontColor=#232F3E;align=left;verticalAlign=top;")

# ===================================================================== people  (x 40..220)
text("People", 40, 110, 180, 24, size=15, color="#232F3E", bold=True)
people = res("Group members<br>developers · engineers<br>researchers", 85, 170, "users", "#232F3D", 64)
manager = res("Engineering manager<br>approves group schedules", 90, 420, "user", "#232F3D", 56)

# ===================================================================== Backstage  (x 280..740)
BX, BW = 280, 460
bs = box("", BX, 110, BW, 560, fill="#F1F5FB", stroke="#1F5FBF")
brand("", BX + 20, 126, "backstage", 30, tile="#121212")
text("Backstage — developer portal (run locally)", BX + 66, 128, 380, 24, size=15, color="#1F5FBF", bold=True)
bs_forms = box("<b>Software templates / forms</b><br>environment · tier · resource sets<br>"
               "tags: owner.team · Reason · LongLive", BX + 20, 180, BW - 40, 70)
bs_const = box("<b>Environment constants</b><br>organisation · group · account ID · region<br>"
               "state bucket · deploy role (from the account registry)", BX + 20, 264, BW - 40, 70)
bs_orch = box("<b>Orchestrator</b><br>apply: ① core-network → ② core-platform → ③ data-rds / -elasticache / -msk<br>"
              "observability before core-platform · destroy in reverse · independent: dns, ecr",
              BX + 20, 348, BW - 40, 84)
bs_life = box("<b>Lifecycle</b><br>personal sandbox: torn down Friday evening or when idle<br>"
              "group schedule (manager-approved): up Monday, down Friday<br>LongLive: kept",
              BX + 20, 446, BW - 40, 84)
bs_app = box("<b>GitHub App</b><br>opens the PR · merges sandbox PRs itself (ruleset bypass)",
             BX + 20, 544, BW - 40, 56)
brand("", BX + 26, 618, "grafana", 22)
text("Grafana plugin: each environment's dashboards next to the environment", BX + 56, 618, BW - 80, 40)

# ===================================================================== account vending  (below Backstage)
box("", BX, 730, BW, 300, fill="#FDF2F8", stroke="#E7157B", extra="dashed=1;")
text("Account vending — separate repo / workflow", BX + 20, 742, 330, 24, size=14, color="#E7157B", bold=True)
stacksets = svc("CloudFormation<br>StackSets", BX + 40, 800, "cloudformation", MGMT)
orgs = svc("AWS Organizations<br>new group account", BX + 200, 800, "organizations", MGMT)
ddb = svc("DynamoDB<br>account registry", BX + 360, 800, "dynamodb", DB)
text("Runs first when a group has no account yet: creates the account, its S3 state bucket and "
     "deploy role, and records them in DynamoDB. Backstage reads the registry into its constants.",
     BX + 20, 940, BW - 40, 70)

# ===================================================================== GitHub  (x 820..1260)
GX, GW = 880, 440
box("", GX, 110, GW, 920, fill="#F6F8FA", stroke="#24292F")
brand("", GX + 20, 124, "github", 32)
text("GitHub", GX + 62, 128, 200, 24, size=16, color="#24292F", bold=True)
repo = box("<b>Repo: infrastructure</b><br><br>"
           "<b>environments/</b>&lt;env&gt;/&lt;scope&gt;/&lt;resource-set&gt;.yaml<br>"
           "&nbsp;&nbsp;one file per unit, written by Backstage<br>"
           "&nbsp;&nbsp;organisation · group · requester · tier · account<br>"
           "&nbsp;&nbsp;state · role_arn · tags · module_ref · spec<br><br>"
           "<b>modules/</b> — plain Terraform roots<br>"
           "&nbsp;&nbsp;context: naming · mandatory tags · VPC lookup<br>"
           "&nbsp;&nbsp;core-network · core-platform · dns<br>"
           "&nbsp;&nbsp;data-rds · data-elasticache · data-msk<br>"
           "&nbsp;&nbsp;ecr (pull-through) · observability<br>"
           "&nbsp;&nbsp;credentials (library)<br><br>"
           "<b>Approval</b><br>"
           "&nbsp;&nbsp;sandbox: merged by Backstage, no review<br>"
           "&nbsp;&nbsp;stage / UAT / prod: approvers from Backstage groups (later)",
           GX + 20, 176, GW - 40, 400)
gha = box("<b>GitHub Actions — terraform.yml</b><br><br>"
          "pull_request: <i>plan</i> each changed YAML<br>"
          "workflow_dispatch: <i>plan | apply | destroy</i> one YAML<br><br>"
          "1. checkout YAML (main) + modules at module_ref<br>"
          "2. OIDC → deploy role from the YAML<br>"
          "3. terraform init — S3 backend from the YAML<br>"
          "&nbsp;&nbsp;&nbsp;&nbsp;key &lt;env&gt;/&lt;scope&gt;/&lt;resource-set&gt;<br>"
          "4. terraform plan / apply / destroy<br><br>"
          "sandbox: module_ref = main<br>"
          "stage / UAT / prod: release tag (v0.1.0 …)<br>"
          "no Terragrunt · no helper scripts",
          GX + 20, 640, GW - 40, 330, extra="spacingLeft=60;")
brand("", GX + 34, 652, "githubactions", 28)
brand("", GX + 34, 690, "terraform", 28)

# ===================================================================== AWS  (x 1340..2480)
AX = 1420
group("AWS Cloud", AX, 110, 1160, 1360, "group_aws_cloud_alt", "#232F3E", font="#232F3E")
group("Group account (one per group) — e.g. vision", AX + 20, 150, 1120, 950, "group_account", "#CD2264")

role = res("IAM deploy role<br>trusts GitHub OIDC", AX + 60, 200, "role", SEC)
s3 = svc("S3 state bucket<br>one state per unit", AX + 220, 200, "s3", STORAGE)
kms_state = svc("KMS<br>state key", AX + 380, 200, "key_management_service", SEC)
r53 = svc("Route 53 (global scope)<br>public + internal zones", AX + 540, 200, "route_53", NET)
text("<b>Names</b> &lt;group&gt;-&lt;env&gt;[-&lt;requester&gt;]-&lt;region code&gt;<br>"
     "<b>Tags</b> Project=Phoenix · Organisation · Group · Requester · owner.team · Reason · LongLive · CreatedBy",
     AX + 740, 196, 380, 80)

group("Region eu-west-1 (one per scope)", AX + 40, 330, 1080, 750, "group_region", "#00A4A6", dashed=1)
vpc = group("VPC per environment — CIDR allocated from IPAM", AX + 60, 370, 760, 690, "group_vpc2", "#8C4FFF")

group("Public subnets (×3 AZ)", AX + 80, 410, 720, 120, "group_security_group", "#7AA116",
      fill="#F2F6E8", font="#248814", extra="grStroke=0;")
nat = res("NAT gateway", AX + 160, 440, "nat_gateway", NET, 48)
igw = res("Internet gateway", AX + 340, 440, "internet_gateway", NET, 48)

group("Private platform subnets (×3 AZ) — core-platform", AX + 80, 550, 720, 290, "group_security_group",
      "#00A4A6", fill="#E6F6F7", font="#147EBA", extra="grStroke=0;")
eks = svc("Amazon EKS<br>clusters 1–20", AX + 110, 590, "eks", COMPUTE)
nodes = res("Node groups<br>+ Karpenter", AX + 250, 590, "instances", COMPUTE)
gpu = res("GPU nodes (vLLM)<br>scale to zero", AX + 390, 590, "instances", COMPUTE)
brand("", AX + 432, 578, "nvidia", 22)
sqs = svc("SQS<br>Karpenter interruption", AX + 530, 590, "sqs", INTEG)
podid = svc("IAM<br>Pod Identity", AX + 680, 590, "identity_and_access_management", SEC)

incl = box("<b>In-cluster</b> (deployed from the next repo)", AX + 100, 690, 680, 130, fill="#FFFFFF", stroke="#147EBA",
           extra="dashed=1;")
brand("vLLM<br>/metrics · OTel", AX + 130, 724, "vllm", 34)
brand("NVIDIA DCGM<br>GPU metrics", AX + 230, 724, "nvidia", 34)
brand("OTel / Alloy<br>collector", AX + 330, 724, "opentelemetry", 34)
brand("Prometheus<br>→ Mimir", AX + 430, 724, "prometheus", 34)
graf = brand("Grafana<br>Loki · Tempo", AX + 530, 724, "grafana", 34)
lf = brand("Langfuse<br>+ ClickHouse", AX + 660, 724, "langfuse", 34)
group("Private data subnets (×3 AZ) — data-*", AX + 80, 860, 720, 180, "group_security_group",
      "#00A4A6", fill="#E6F6F7", font="#147EBA", extra="grStroke=0;")
rds = svc("Amazon RDS PostgreSQL<br>apps + Langfuse", AX + 130, 900, "rds", DB)
ec = svc("ElastiCache Valkey<br>apps + Langfuse", AX + 320, 900, "elasticache", DB)
msk = svc("Amazon MSK<br>Kafka, IAM auth", AX + 500, 900, "managed_streaming_for_kafka", ANALYTICS)
tgwa = res("TGW attachment", AX + 670, 904, "transit_gateway", NET, 48)

text("Account-level, per region", AX + 850, 370, 250, 24, size=13, color="#232F3E", bold=True)
ecr = svc("ECR pull-through<br>cache artifactory/…", AX + 870, 410, "ecr", COMPUTE, 48)
sm = svc("Secrets Manager<br>&lt;org&gt;/&lt;env&gt;/…", AX + 1010, 410, "secrets_manager", SEC, 48)
kms = svc("KMS<br>data keys", AX + 870, 520, "key_management_service", SEC, 48)
ecr_role = res("IAM role<br>ECR pull-through", AX + 1010, 520, "role", SEC, 48)

box("", AX + 845, 640, 260, 300, fill="#F2F6E8", stroke="#7AA116", extra="dashed=1;")
text("<b>observability</b> — LongLive,<br>survives weekend teardown", AX + 855, 646, 240, 40, size=12, color="#248814")
obs = svc("S3 observability bucket<br>&lt;signal&gt;/&lt;cluster&gt;/…", AX + 951, 700, "s3", STORAGE, 48)
obs_kms = svc("KMS", AX + 880, 820, "key_management_service", SEC, 44)
obs_roles = res("Pod Identity roles<br>per writer", AX + 1010, 820, "role", SEC, 44)
cw = svc("CloudWatch<br>RDS · cache · MSK · ALB", AX + 951, 960, "cloudwatch_2", MGMT, 44)
group("Networking account", AX + 20, 1130, 540, 320, "group_account", "#CD2264")
tgw = res("Transit Gateway<br>per region, RAM-shared", AX + 120, 1190, "transit_gateway", NET)
ipam = svc("VPC IPAM pools<br>nonprod · prod · infrastructure", AX + 340, 1190, "vpc", NET)
text("Owned outside this repo. core-network attaches each VPC to the transit gateway and allocates its "
     "CIDR from IPAM, so overlap is IPAM's job.", AX + 40, 1350, 500, 60)

group("Management (delegated admin) / shared tooling accounts", AX + 580, 1130, 560, 320, "group_account", "#CD2264")
parent = res("Route 53 parent zone<br>NS delegation", AX + 630, 1190, "hosted_zone", NET)
hub = svc("ECR hub<br>(central)", AX + 800, 1190, "ecr", COMPUTE)
artifactory = brand("Artifactory<br>(company)", AX + 980, 1194, "jfrog", 48)
brand("", AX + 900, 1300, "githubactions", 22)
text("scheduled sync<br>regsync / skopeo", AX + 928, 1296, 160, 40, size=11)
text("Hub, its registry policy and the sync are outside this repo; each group account caches from the hub on first pull.",
     AX + 600, 1380, 520, 40)


# ===================================================================== flows
edge(people, bs_forms, "request", exit_=(1, 0.5), entry=(0, 0.5))
edge(manager, bs_life, "approve schedule", exit_=(1, 0.5), entry=(0, 0.5))
edge(bs_const, stacksets, "① no group account", dashed=True, exit_=(0, 0.5), entry=(0, 0.5),
     points=[(250, 299), (250, 828)])
edge(stacksets, orgs, "create", exit_=(1, 0.5), entry=(0, 0.5))
edge(orgs, ddb, "record", exit_=(1, 0.5), entry=(0, 0.5))
edge(ddb, bs, "② read", dashed=True, exit_=(0.5, 0), entry=(0.835, 1))
edge(bs_app, repo, "③ PR adds YAML", exit_=(1, 0.5), entry=(0, 0.92))
edge(bs_orch, gha, "④ dispatch, in order", exit_=(1, 0.75), entry=(0, 0.12), points=[(820, 411), (820, 680)])
edge(repo, gha, "YAML + modules", exit_=(0.5, 1), entry=(0.5, 0))
edge(gha, role, "⑤ OIDC → AssumeRole", exit_=(1, 0.1), entry=(0, 0.5), points=[(AX - 40, 673), (AX - 40, 228)])
edge(role, s3, "state", dashed=True, exit_=(1, 0.5), entry=(0, 0.5))
edge(ipam, vpc, "allocate CIDR", dashed=True, exit_=(0.5, 0), entry=(0.405, 1))
edge(tgwa, tgw, "attach", dashed=True, exit_=(0.5, 1), entry=(0.5, 0), points=[(AX + 694, 1115), (AX + 148, 1115)])
edge(r53, parent, "NS delegation", dashed=True, exit_=(1, 0.5), entry=(0.5, 0), points=[(AX + 1150, 228), (AX + 1150, 1118), (AX + 658, 1118)])
edge(artifactory, hub, "sync", exit_=(0, 0.5), entry=(1, 0.5))
edge(hub, ecr, "pull-through cache", dashed=True, exit_=(0.5, 0), entry=(0.5, 0),
     points=[(AX + 828, 1150), (AX + 1128, 1150), (AX + 1128, 400), (AX + 894, 400)])
edge(lf, rds, "", dashed=True, exit_=(0.5, 1), entry=(1, 0.3), points=[(AX + 677, 880), (AX + 250, 880)])
edge(incl, obs, "metrics · logs · traces", exit_=(1, 0.5), entry=(0, 0.5), points=[(AX + 830, 755), (AX + 830, 724)])
edge(graf, cw, "read", dashed=True, exit_=(0.5, 1), entry=(0, 0.5), points=[(AX + 547, 850), (AX + 840, 850), (AX + 840, 982)])

xml = ('<mxfile host="drawio"><diagram id="phoenix" name="Phoenix architecture">'
       '<mxGraphModel dx="2700" dy="1400" grid="0" gridSize="10" guides="1" tooltips="1" connect="1" arrows="1" '
       'fold="1" page="0" pageScale="1" pageWidth="2700" pageHeight="1520" math="0" shadow="0" background="#FFFFFF">'
       '<root><mxCell id="0"/><mxCell id="1" parent="0"/>' + "".join(cells) +
       '</root></mxGraphModel></diagram></mxfile>')
(HERE / "phoenix-architecture.drawio").write_text(xml)
print("wrote", HERE / "phoenix-architecture.drawio", len(cells), "cells")
