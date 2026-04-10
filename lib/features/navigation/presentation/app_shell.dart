import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:go_router/go_router.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:sage/core/theme/app_colors.dart';
import 'package:sage/shared/widgets/offline_banner.dart';
import 'package:sage/features/navigation/presentation/widgets/bottom_context_action.dart';
import 'package:sage/features/navigation/presentation/widgets/mode_selector.dart';

/// App Shell — Mode selector at top, voice button at bottom.
///
/// Three mode glyphs replace the tab bar.
/// Profile icon top-right. Voice button bottom-center.
/// Swipe horizontally to transition modes.
class AppShell extends StatelessWidget {
  final StatefulNavigationShell navigationShell;

  const AppShell({super.key, required this.navigationShell});

  void _handleSwipe(DragEndDetails details) {
    if (details.primaryVelocity == null) return;
    const sensitivity = 8;
    // Swipe Right (Velocity > 0) -> Go Back (Index - 1)
    if (details.primaryVelocity! > sensitivity) {
      if (navigationShell.currentIndex > 0) {
        HapticFeedback.selectionClick();
        navigationShell.goBranch(
          navigationShell.currentIndex - 1,
          initialLocation: true,
        );
      }
    }
    // Swipe Left (Velocity < 0) -> Go Next (Index + 1)
    else if (details.primaryVelocity! < -sensitivity) {
      if (navigationShell.currentIndex < 2) {
        HapticFeedback.selectionClick();
        navigationShell.goBranch(
          navigationShell.currentIndex + 1,
          initialLocation: true,
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.sage;
    final topPad = MediaQuery.of(context).padding.top;
    final bottomPad = MediaQuery.of(context).padding.bottom;

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light.copyWith(
        statusBarColor: Colors.transparent,
        systemNavigationBarColor: c.background,
      ),
      child: Scaffold(
        backgroundColor: c.background,
        body: GestureDetector(
          onHorizontalDragEnd: _handleSwipe,
          behavior: HitTestBehavior.translucent,
          child: Stack(
            children: [
              // ── Main content ──
              navigationShell,

              // ── Offline banner — slides in below the status bar ──
              Positioned(
                top: topPad,
                left: 0,
                right: 0,
                child: const OfflineBanner(),
              ),

              // ── Mode selector — top center ──
              Positioned(
                top: topPad + 8.h,
                left: 0,
                right: 0,
                child: ModeSelector(
                  activeIndex: navigationShell.currentIndex,
                  onTap: (i) {
                    HapticFeedback.selectionClick();
                    navigationShell.goBranch(
                      i,
                      initialLocation: i == navigationShell.currentIndex,
                    );
                  },
                ),
              ),

              // ── Profile icon — top right ──
              Positioned(
                top: topPad + 12.h,
                right: 20.w,
                child: GestureDetector(
                  onTap: () {
                    HapticFeedback.selectionClick();
                    context.push('/profile');
                  },
                  child: Container(
                    width: 32.w,
                    height: 32.w,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: c.surface,
                      border: Border.all(color: c.border, width: 1),
                    ),
                    child: Center(
                      child: Icon(
                        PhosphorIconsBold.user,
                        size: 16.sp,
                        color: c.textSecondary,
                      ),
                    ),
                  ),
                ),
              ),

              // ── Voice button — bottom center (only on Automate tab as "New Strategy") ──
              if (navigationShell.currentIndex == 2)
                Positioned(
                  bottom: bottomPad + 16.h,
                  left: 0,
                  right: 0,
                  child: Center(
                    child: BottomContextAction(
                      currentIndex: navigationShell.currentIndex,
                      onHomeVoiceTap: () {
                        HapticFeedback.selectionClick();
                        navigationShell.goBranch(1, initialLocation: true);
                      },
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
