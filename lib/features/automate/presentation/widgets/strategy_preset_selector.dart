import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

import 'package:sage/core/models/strategy.dart';
import 'package:sage/core/repositories/strategy_repository.dart';
import 'package:sage/core/theme/app_colors.dart';

/// Preset selector that fetches strategies from the backend
/// and displays them as selectable chips.
class StrategyPresetSelector extends ConsumerWidget {
  final StrategyPreset? selectedPreset;
  final ValueChanged<StrategyPreset> onPresetSelected;
  final VoidCallback onCustomSelected;
  final SageColors c;
  final TextTheme text;

  const StrategyPresetSelector({
    super.key,
    required this.selectedPreset,
    required this.onPresetSelected,
    required this.onCustomSelected,
    required this.c,
    required this.text,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final presetsAsync = ref.watch(strategyPresetsProvider);

    return presetsAsync.when(
      skipLoadingOnReload: true,
      loading: () => Container(
        padding: EdgeInsets.symmetric(vertical: 14.h),
        decoration: BoxDecoration(
          color: c.surface,
          borderRadius: BorderRadius.circular(12.r),
          border: Border.all(color: c.borderSubtle),
        ),
        child: Center(
          child: SizedBox(
            width: 16.w,
            height: 16.w,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              color: c.textTertiary,
            ),
          ),
        ),
      ),
      error: (_, _) => Container(
        padding: EdgeInsets.symmetric(vertical: 14.h, horizontal: 16.w),
        decoration: BoxDecoration(
          color: c.surface,
          borderRadius: BorderRadius.circular(12.r),
          border: Border.all(color: c.borderSubtle),
        ),
        child: Text(
          'Custom (presets unavailable)',
          style: text.labelMedium?.copyWith(
            color: c.textTertiary,
            fontSize: 12.sp,
          ),
        ),
      ),
      data: (presets) {
        final isCustom = selectedPreset == null;
        return Wrap(
          spacing: 8.w,
          runSpacing: 8.h,
          children: [
            // Custom chip
            PresetChip(
              label: 'Custom',
              isSelected: isCustom,
              onTap: onCustomSelected,
              c: c,
              text: text,
            ),
            // Preset chips
            ...presets.map(
              (preset) => PresetChip(
                label: preset.name,
                isSelected: selectedPreset?.id == preset.id,
                onTap: () => onPresetSelected(preset),
                c: c,
                text: text,
              ),
            ),
          ],
        );
      },
    );
  }
}

/// Individual preset chip — animated selection state.
class PresetChip extends StatelessWidget {
  final String label;
  final bool isSelected;
  final VoidCallback onTap;
  final SageColors c;
  final TextTheme text;

  const PresetChip({
    super.key,
    required this.label,
    required this.isSelected,
    required this.onTap,
    required this.c,
    required this.text,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: EdgeInsets.symmetric(horizontal: 14.w, vertical: 8.h),
        decoration: BoxDecoration(
          color: isSelected ? c.accent : c.surface,
          borderRadius: BorderRadius.circular(20.r),
          border: Border.all(
            color: isSelected ? c.accent : c.borderSubtle,
            width: isSelected ? 1.5 : 1,
          ),
        ),
        child: Text(
          label,
          style: text.labelMedium?.copyWith(
            fontWeight: FontWeight.w700,
            color: isSelected ? c.textPrimary : c.textTertiary,
            fontSize: 12.sp,
          ),
        ),
      ),
    );
  }
}
