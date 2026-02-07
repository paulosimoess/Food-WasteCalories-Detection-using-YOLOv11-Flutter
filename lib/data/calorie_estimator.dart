class CalorieEstimator {
  final double gramsFullPlate;     // prato cheio médio
  final double maxPortionPerItem;  // máximo por item
  final double maxGramsItem;
  final double minGramsItem;

  CalorieEstimator({
    this.gramsFullPlate = 600.0,
    this.maxPortionPerItem = 0.70,
    this.maxGramsItem = 350.0,
    this.minGramsItem = 10.0,
  });

  double gramsFromPortion(double portion) {
    final p = portion.clamp(0.0, 1.0);
    return (p * gramsFullPlate).clamp(0.0, maxGramsItem);
  }

  double kcalFromGrams({required double grams, required double kcalPer100g}) {
    return (grams / 100.0) * kcalPer100g;
  }
}