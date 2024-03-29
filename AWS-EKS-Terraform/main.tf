resource "aws_vpc" "project_vpc" {
    cidr_block       = var.vpc_cidr
    instance_tenancy = "default"

    tags = {
        Name = "Project"
    }
}

resource "aws_subnet" "public-subnet-1" {
    vpc_id = aws_vpc.project_vpc.id
    cidr_block = var.public_sb1_cidr
    availability_zone = "us-east-1a"
    map_public_ip_on_launch = true
    tags = {
        Name = "public-subnet-1"
    }
}

resource "aws_subnet" "private-subnet-1" {
    vpc_id = aws_vpc.project_vpc.id
    cidr_block = var.private_sb1_cidr
    availability_zone = "us-east-1a"
    tags = {
        Name = "private-subnet-1"
    }
}

resource "aws_subnet" "public-subnet-2" {
    vpc_id = aws_vpc.project_vpc.id
    cidr_block = var.public_sb2_cidr
    availability_zone = "us-east-1b"
    map_public_ip_on_launch = true
    tags = {
        Name = "public-subnet-2"
    }
}

resource "aws_subnet" "private-subnet-2" {
    vpc_id = aws_vpc.project_vpc.id
    cidr_block = var.private_sb2_cidr
    availability_zone = "us-east-1b"
    tags = {
        Name = "private-subnet-2"
    }
}

resource "aws_internet_gateway" "igw" {
    vpc_id = aws_vpc.project_vpc.id
    tags = {
        Name = "iqw"
    }
} 

resource "aws_route_table" "public_route_table" {
    vpc_id = aws_vpc.project_vpc.id
    route {
        cidr_block = "0.0.0.0/0"
        gateway_id = aws_internet_gateway.igw.id
    }
    tags = {
        Name = "public-route-table"
    }
}

resource "aws_route_table_association" "rta_to_public1" {
    subnet_id      = aws_subnet.public-subnet-1.id
    route_table_id = aws_route_table.public_route_table.id
}

resource "aws_route_table_association" "rta_to_public2" {
    subnet_id      = aws_subnet.public-subnet-2.id
    route_table_id = aws_route_table.public_route_table.id
}

resource "aws_eip" "eip" {
    network_border_group = "us-east-1"
    tags = {
        Name = "eip"
    }
}  

resource "aws_nat_gateway" "nat_gw" {
    allocation_id = aws_eip.eip.id
    subnet_id = aws_subnet.private-subnet-1.id
    tags = {
        Name = "nat-gw"
    }
}

resource "aws_route_table" "private_route_table" {
    vpc_id = aws_vpc.project_vpc.id
    route {
        cidr_block = "0.0.0.0/0"
        gateway_id = aws_nat_gateway.nat_gw.id
    }

    tags = {
        Name = "private-route-table"
    }
}

resource "aws_route_table_association" "rta_to_private1" {
    subnet_id = aws_subnet.private-subnet-1.id
    route_table_id = aws_route_table.private_route_table.id
}

resource "aws_route_table_association" "rta_to_private2" {
    subnet_id = aws_subnet.private-subnet-2.id
    route_table_id = aws_route_table.private_route_table.id
}

#####################################################################################################################################

data "aws_iam_policy_document" "assume_role" {
    statement {
        effect = "Allow"

        principals {
        type        = "Service"
        identifiers = ["eks.amazonaws.com"]
        }

        actions = ["sts:AssumeRole"]
    }
}

resource "aws_iam_role" "eks_cluster_role" {
    name               = "eks-cluster-example"
    assume_role_policy = data.aws_iam_policy_document.assume_role.json
}

resource "aws_iam_role_policy_attachment" "AmazonEKSClusterPolicy" {
    policy_arn = "arn:aws:iam::aws:policy/AmazonEKSClusterPolicy"
    role       = aws_iam_role.eks_cluster_role.name
}

# Optionally, enable Security Groups for Pods
# Reference: https://docs.aws.amazon.com/eks/latest/userguide/security-groups-for-pods.html
# resource "aws_iam_role_policy_attachment" "example-AmazonEKSVPCResourceController" {
#     policy_arn = "arn:aws:iam::aws:policy/AmazonEKSVPCResourceController"
#     role       = aws_iam_role.example.name
# }

resource "aws_eks_cluster" "eks_cluster" {
    name     = "demo-eks"
    role_arn = aws_iam_role.eks_cluster_role.arn

    vpc_config {
        subnet_ids = [aws_subnet.public-subnet-1.id, aws_subnet.public-subnet-2.id]
    }

    # Ensure that IAM Role permissions are created before and deleted after EKS Cluster handling.
    # Otherwise, EKS will not be able to properly delete EKS managed EC2 infrastructure such as Security Groups.
    depends_on = [
        aws_iam_role_policy_attachment.AmazonEKSClusterPolicy
    ]
}


resource "aws_iam_role" "ec2_eks_role" {
    name = "test_role"

    # Terraform's "jsonencode" function converts a
    # Terraform expression result to valid JSON syntax.
    assume_role_policy = jsonencode({
        Version = "2012-10-17"
        Statement = [
        {
            Action = "sts:AssumeRole"
            Effect = "Allow"
            Sid    = ""
            Principal = {
            Service = "ec2.amazonaws.com"
            }
        },
        ]
    })
}

resource "aws_iam_role_policy_attachment" "example-AmazonEKSWorkerNodePolicy" {
    policy_arn = "arn:aws:iam::aws:policy/AmazonEKSWorkerNodePolicy"
    role       = aws_iam_role.ec2_eks_role.name
}

resource "aws_iam_role_policy_attachment" "example-AmazonEKS_CNI_Policy" {
    policy_arn = "arn:aws:iam::aws:policy/AmazonEKS_CNI_Policy"
    role       = aws_iam_role.ec2_eks_role.name
}

resource "aws_iam_role_policy_attachment" "example-AmazonEC2ContainerRegistryReadOnly" {
    policy_arn = "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly"
    role       = aws_iam_role.ec2_eks_role.name
}

resource "aws_eks_node_group" "cluster_node_group" {
    cluster_name    = aws_eks_cluster.eks_cluster.name
    node_group_name = "eks_cluster_group"
    node_role_arn   = aws_iam_role.ec2_eks_role.arn
    subnet_ids      = [aws_subnet.public-subnet-1.id, aws_subnet.public-subnet-2.id]
    instance_types = ["t2.micro"]

    scaling_config {
        desired_size = 1
        max_size     = 2
        min_size     = 1
    }

    update_config {
        max_unavailable = 1
    }

    # Ensure that IAM Role permissions are created before and deleted after EKS Node Group handling.
    # Otherwise, EKS will not be able to properly delete EC2 Instances and Elastic Network Interfaces.
    depends_on = [
        aws_iam_role_policy_attachment.example-AmazonEKSWorkerNodePolicy,
        aws_iam_role_policy_attachment.example-AmazonEKS_CNI_Policy,
        aws_iam_role_policy_attachment.example-AmazonEC2ContainerRegistryReadOnly,
    ]
}




