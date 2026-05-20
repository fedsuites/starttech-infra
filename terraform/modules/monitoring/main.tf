# SNS Topic for alarm notifications
resource "aws_sns_topic" "alerts" {
  name = "${var.project_name}-alerts"

  tags = {
    Name        = "${var.project_name}-alerts"
    Environment = var.environment
  }
}

# SNS Topic Subscription (email)
resource "aws_sns_topic_subscription" "email" {
  count     = var.alarm_email != "" ? 1 : 0
  topic_arn = aws_sns_topic.alerts.arn
  protocol  = "email"
  endpoint  = var.alarm_email
}

# CloudWatch Log Groups


resource "aws_cloudwatch_log_group" "frontend" {
  name              = "/starttech/frontend"
  retention_in_days = var.log_retention_days

  tags = {
    Name        = "${var.project_name}-frontend-logs"
    Environment = var.environment
  }
}

resource "aws_cloudwatch_log_group" "infrastructure" {
  name              = "/starttech/infrastructure"
  retention_in_days = var.log_retention_days

  tags = {
    Name        = "${var.project_name}-infrastructure-logs"
    Environment = var.environment
  }
}

# CloudWatch Dashboard
resource "aws_cloudwatch_dashboard" "main" {
  dashboard_name = "${var.project_name}-dashboard"

  dashboard_body = jsonencode({
    widgets = [
      {
        type = "metric"
        properties = {
          title  = "ALB Request Count"
          region ="us-east-1"
          period = 300
          stat   = "Sum"
          metrics = [
            ["AWS/ApplicationELB", "RequestCount",
            "LoadBalancer", var.alb_arn]
          ]
        }
      },
      {
        type = "metric"
        properties = {
          title  = "ALB Target Response Time"
          region = "us-east-1"
          period = 300
          stat   = "Average"
          metrics = [
            ["AWS/ApplicationELB", "TargetResponseTime",
            "LoadBalancer", var.alb_arn]
          ]
        }
      },
      {
        type = "metric"
        properties = {
          title  = "ASG CPU Utilization"
          region = "us-east-1"
          period = 300
          stat   = "Average"
          metrics = [
            ["AWS/EC2", "CPUUtilization",
            "AutoScalingGroupName", var.asg_name]
          ]
        }
      },
      {
        type = "metric"
        properties = {
          title  = "ALB HTTP 5XX Errors"
          region = "us-east-1"
          period = 300
          stat   = "Sum"
          metrics = [
            ["AWS/ApplicationELB", "HTTPCode_Target_5XX_Count",
            "LoadBalancer", var.alb_arn]
          ]
        }
      },
      {
        type = "log"
        properties = {
          title   = "Backend Application Logs"
          query   = "SOURCE '/starttech/backend' | fields @timestamp, @message | sort @timestamp desc | limit 50"
          region  = "us-east-1"
          view    = "table"
        }
      }
    ]
  })
}

# CloudWatch Alarm - ALB 5XX errors
resource "aws_cloudwatch_metric_alarm" "alb_5xx" {
  alarm_name          = "${var.project_name}-alb-5xx-errors"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 2
  metric_name         = "HTTPCode_Target_5XX_Count"
  namespace           = "AWS/ApplicationELB"
  period              = 60
  statistic           = "Sum"
  threshold           = 10
  alarm_description   = "ALB 5XX errors exceeded threshold"
  alarm_actions       = [aws_sns_topic.alerts.arn]
  ok_actions          = [aws_sns_topic.alerts.arn]
  treat_missing_data  = "notBreaching"

  dimensions = {
    LoadBalancer = var.alb_arn
  }
}

# CloudWatch Alarm - ALB response time
resource "aws_cloudwatch_metric_alarm" "alb_response_time" {
  alarm_name          = "${var.project_name}-alb-response-time"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 2
  metric_name         = "TargetResponseTime"
  namespace           = "AWS/ApplicationELB"
  period              = 60
  statistic           = "Average"
  threshold           = 2
  alarm_description   = "ALB response time exceeded 2 seconds"
  alarm_actions       = [aws_sns_topic.alerts.arn]
  treat_missing_data  = "notBreaching"

  dimensions = {
    LoadBalancer = var.alb_arn
  }
}

# CloudWatch Alarm - Unhealthy hosts
resource "aws_cloudwatch_metric_alarm" "unhealthy_hosts" {
  alarm_name          = "${var.project_name}-unhealthy-hosts"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 1
  metric_name         = "UnHealthyHostCount"
  namespace           = "AWS/ApplicationELB"
  period              = 60
  statistic           = "Average"
  threshold           = 0
  alarm_description   = "One or more backend hosts are unhealthy"
  alarm_actions       = [aws_sns_topic.alerts.arn]
  ok_actions          = [aws_sns_topic.alerts.arn]
  treat_missing_data  = "notBreaching"

  dimensions = {
    LoadBalancer = var.alb_arn
    TargetGroup  = var.target_group_arn
  }
}