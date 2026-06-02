# ==============================================
# IAM 역할 및 정책 설정
# ==============================================
# EC2 인스턴스가 AWS 서비스에 접근할 수 있도록 IAM 역할 정의
# - SSM(Systems Manager): EC2 Instance Connect 및 원격 명령 실행
# - ECR(Elastic Container Registry): Docker 이미지 다운로드

resource "aws_iam_role" "ec2_instance_role" {
  name = "${local.name_prefix}-ec2-role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "ec2.amazonaws.com"
        }
      }
    ]
  })

  tags = {
    Name        = "${local.name_prefix}-ec2-role"
    Environment = local.env
  }
}

# SSM 매니지드 정책 연결: EC2에서 Systems Manager 사용 가능
resource "aws_iam_role_policy_attachment" "ssm" {
  role       = aws_iam_role.ec2_instance_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

# ECR 읽기 정책 연결: Docker 이미지를 ECR에서 다운로드 가능
resource "aws_iam_role_policy_attachment" "ecr_readonly" {
  role       = aws_iam_role.ec2_instance_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly"
}

# EC2 자기 자신의 Name 태그를 갱신할 수 있도록 허용
resource "aws_iam_role_policy" "ec2_self_tag" {
  name = "${local.name_prefix}-ec2-self-tag"
  role = aws_iam_role.ec2_instance_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = ["ec2:CreateTags"]
      Resource = "arn:aws:ec2:*:*:instance/*"
    }]
  })
}

# IAM 인스턴스 프로파일 생성: EC2가 IAM 역할을 사용할 수 있도록 설정
resource "aws_iam_instance_profile" "instance_profile" {
  name = "${local.name_prefix}-instance-profile"
  role = aws_iam_role.ec2_instance_role.name
}
