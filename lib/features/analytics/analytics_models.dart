/// Analytics and KPI models
library;

class MaintenanceMetrics {
  final double mtbf; // Mean Time Between Failures (hours)
  final double mttr; // Mean Time To Repair (hours)
  final double oee; // Overall Equipment Effectiveness (%)
  final double availability; // Equipment availability (%)
  final int totalBreakdowns;
  final int totalWorkOrders;
  final double totalDowntimeHours;
  final double totalMaintenanceCost;
  final DateTime period; // Start date for this metrics period

  const MaintenanceMetrics({
    required this.mtbf,
    required this.mttr,
    required this.oee,
    required this.availability,
    required this.totalBreakdowns,
    required this.totalWorkOrders,
    required this.totalDowntimeHours,
    required this.totalMaintenanceCost,
    required this.period,
  });

  /// Calculate MTBF: Total running hours / Number of failures
  static double calculateMTBF(double totalRunningHours, int failureCount) {
    return failureCount > 0 ? totalRunningHours / failureCount : 0;
  }

  /// Calculate MTTR: Total downtime / Number of repairs
  static double calculateMTTR(double totalDowntimeHours, int repairCount) {
    return repairCount > 0 ? totalDowntimeHours / repairCount : 0;
  }

  /// Calculate OEE: (Availability * Performance * Quality) * 100
  /// For maintenance: (Available hours / Total hours) * (Planned production / Actual production) * (Good production / Total production)
  /// Simplified: Availability * 100
  static double calculateOEE(double availability) {
    return availability * 100;
  }

  /// Calculate availability: Running hours / Total available hours
  static double calculateAvailability(double runningHours, double totalHours) {
    return totalHours > 0 ? runningHours / totalHours : 0;
  }
}

/// Failure frequency analysis (Pareto)
class FailureCategory {
  final String category;
  final int count;
  final double percentage;
  final double cumulativePercentage;

  const FailureCategory({
    required this.category,
    required this.count,
    required this.percentage,
    required this.cumulativePercentage,
  });
}

class ParetoAnalysis {
  final List<FailureCategory> categories;
  final int total;

  const ParetoAnalysis({required this.categories, required this.total});

  /// Calculate Pareto: Sort by frequency and calculate cumulative %
  static ParetoAnalysis calculate(Map<String, int> failureCounts) {
    // Sort by count (descending)
    final sorted = failureCounts.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    final total = failureCounts.values.fold<int>(0, (sum, v) => sum + v);
    double cumulative = 0;

    final categories = sorted.map((entry) {
      final percentage = (entry.value / total) * 100;
      cumulative += percentage;
      return FailureCategory(
        category: entry.key,
        count: entry.value,
        percentage: percentage,
        cumulativePercentage: cumulative,
      );
    }).toList();

    return ParetoAnalysis(categories: categories, total: total);
  }
}

/// Cost analysis
class CostBreakdown {
  final String category;
  final double amount;
  final double percentage;

  const CostBreakdown({
    required this.category,
    required this.amount,
    required this.percentage,
  });
}

class CostAnalysis {
  final List<CostBreakdown> breakdown;
  final double totalCost;
  final double pmCost;
  final double cmCost;
  final double sparePartsCost;

  const CostAnalysis({
    required this.breakdown,
    required this.totalCost,
    required this.pmCost,
    required this.cmCost,
    required this.sparePartsCost,
  });

  /// Get PM vs CM cost ratio
  double get pmToCmRatio => cmCost > 0 ? pmCost / cmCost : 0;

  /// Recommendation: Should be PM > 50%
  String get recommendation {
    final pmPercentage = (pmCost / totalCost) * 100;
    if (pmPercentage < 30) {
      return 'Focus on preventive maintenance - currently only ${pmPercentage.toStringAsFixed(1)}% of budget';
    } else if (pmPercentage > 70) {
      return 'Good PM ratio - ${pmPercentage.toStringAsFixed(1)}% of budget is preventive';
    }
    return 'Balanced maintenance strategy';
  }
}

/// Failure prediction model
class FailurePrediction {
  final String machineId;
  final String machineNo;
  final double riskScore; // 0-100, higher = higher risk
  final String riskLevel; // Low, Medium, High, Critical
  final String? reason; // Why at risk
  final DateTime? estimatedFailureDate;

  const FailurePrediction({
    required this.machineId,
    required this.machineNo,
    required this.riskScore,
    required this.riskLevel,
    this.reason,
    this.estimatedFailureDate,
  });

  /// Simple risk calculation based on MTBF trend
  static double calculateRiskScore(
    double currentMTBF,
    double averageMTBF,
    int recentFailures,
  ) {
    double score = 0;

    // If MTBF is decreasing (worse than average), increase risk
    if (currentMTBF < averageMTBF) {
      score += ((averageMTBF - currentMTBF) / averageMTBF) * 40;
    }

    // If multiple failures recently, increase risk
    if (recentFailures > 3) {
      score += (recentFailures * 10).clamp(0, 40);
    }

    return score.clamp(0, 100);
  }

  String get riskLevelLabel {
    if (riskScore >= 75) return 'Critical';
    if (riskScore >= 50) return 'High';
    if (riskScore >= 25) return 'Medium';
    return 'Low';
  }

  static String _getRiskLevel(double score) {
    if (score >= 75) return 'Critical';
    if (score >= 50) return 'High';
    if (score >= 25) return 'Medium';
    return 'Low';
  }

  static FailurePrediction fromCalculation({
    required String machineId,
    required String machineNo,
    required double currentMTBF,
    required double averageMTBF,
    required int recentFailures,
  }) {
    final riskScore = calculateRiskScore(
      currentMTBF,
      averageMTBF,
      recentFailures,
    );
    final riskLevel = _getRiskLevel(riskScore);

    String? reason;
    if (currentMTBF < averageMTBF) {
      reason =
          'MTBF is decreasing (${currentMTBF.toStringAsFixed(0)} vs avg ${averageMTBF.toStringAsFixed(0)} hours)';
    }
    if (recentFailures > 3) {
      reason =
          '${reason != null ? '$reason; ' : ''}$recentFailures failures in recent period';
    }

    return FailurePrediction(
      machineId: machineId,
      machineNo: machineNo,
      riskScore: riskScore,
      riskLevel: riskLevel,
      reason: reason,
      estimatedFailureDate: null, // Would require time series analysis
    );
  }
}

/// Trend data point
class TrendDataPoint {
  final DateTime date;
  final double value;

  const TrendDataPoint({required this.date, required this.value});
}

/// Trend analysis
class TrendAnalysis {
  final List<TrendDataPoint> mtbfTrend;
  final List<TrendDataPoint> mttrTrend;
  final String mtbfDirection; // up, down, stable
  final String mttrDirection;
  final double mtbfChangePercent;
  final double mttrChangePercent;

  const TrendAnalysis({
    required this.mtbfTrend,
    required this.mttrTrend,
    required this.mtbfDirection,
    required this.mttrDirection,
    required this.mtbfChangePercent,
    required this.mttrChangePercent,
  });

  /// Calculate trend direction and change percentage
  static (String, double) calculateTrend(List<TrendDataPoint> data) {
    if (data.isEmpty) return ('stable', 0);

    final oldValue = data.first.value;
    final newValue = data.last.value;
    final changePercent = ((newValue - oldValue) / oldValue * 100).abs();

    String direction;
    if (newValue > oldValue) {
      direction = 'up';
    } else if (newValue < oldValue) {
      direction = 'down';
    } else {
      direction = 'stable';
    }

    return (direction, changePercent);
  }
}
