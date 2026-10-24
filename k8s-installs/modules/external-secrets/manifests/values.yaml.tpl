serviceAccount:
  create: true
  name: ${service_account_name}

%{ if app_version != "" ~}
image:
  tag: "${app_version}"
%{ endif ~}
