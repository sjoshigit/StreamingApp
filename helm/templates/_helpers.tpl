{{/*
Construct the dynamic ECR registry URL
*/}}
{{- define "streamingapp.registry" -}}
{{- printf "%s.dkr.ecr.%s.amazonaws.com" .Values.aws.accountId .Values.global.awsRegion -}}
{{- end }}

{{/*
Construct the dynamic IAM Role ARN for IRSA
*/}}
{{- define "streamingapp.roleArn" -}}
{{- printf "arn:aws:iam::%s:role/%s" .Values.aws.accountId .Values.aws.roleName -}}
{{- end }}