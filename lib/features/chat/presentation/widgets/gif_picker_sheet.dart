import 'dart:async';
import 'dart:convert';
import 'dart:io' show Platform;

import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:http/http.dart' as http;

final String _giphyApiKey = Platform.isIOS
    ? 'lCEv74LguEQZ1DbDvHJ7I1TqVQ2UZT0b'
    : 'bTicBinMyIhFn7ZnnqvSD3fZBM3HSzzb';

class GifPickerSheet extends StatefulWidget {
  const GifPickerSheet({super.key});

  @override
  State<GifPickerSheet> createState() => _GifPickerSheetState();
}

class _GifPickerSheetState extends State<GifPickerSheet> {
  final _searchController = TextEditingController();
  List<_GifItem> _gifs = [];
  bool _loading = true;
  Timer? _debounce;

  @override
  void initState() {
    super.initState();
    _loadTrending();
  }

  @override
  void dispose() {
    _searchController.dispose();
    _debounce?.cancel();
    super.dispose();
  }

  Future<void> _loadTrending() async {
    setState(() => _loading = true);
    try {
      final uri = Uri.parse(
        'https://api.giphy.com/v1/gifs/trending?api_key=$_giphyApiKey&limit=30&rating=g',
      );
      final resp = await http.get(uri);
      if (resp.statusCode == 200) {
        _parseResponse(resp.body);
      }
    } catch (_) {}
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _search(String query) async {
    if (query.trim().isEmpty) {
      _loadTrending();
      return;
    }
    setState(() => _loading = true);
    try {
      final uri = Uri.parse(
        'https://api.giphy.com/v1/gifs/search?api_key=$_giphyApiKey&q=${Uri.encodeComponent(query)}&limit=30&rating=g',
      );
      final resp = await http.get(uri);
      if (resp.statusCode == 200) {
        _parseResponse(resp.body);
      }
    } catch (_) {}
    if (mounted) setState(() => _loading = false);
  }

  void _parseResponse(String body) {
    final json = jsonDecode(body) as Map<String, dynamic>;
    final data = json['data'] as List<dynamic>? ?? [];
    _gifs = data.map((item) {
      final images = item['images'] as Map<String, dynamic>? ?? {};
      final preview =
          images['fixed_width_small'] as Map<String, dynamic>? ?? {};
      final original = images['original'] as Map<String, dynamic>? ?? {};
      return _GifItem(
        previewUrl: preview['url'] as String? ?? '',
        fullUrl: original['url'] as String? ?? '',
      );
    }).where((g) => g.previewUrl.isNotEmpty && g.fullUrl.isNotEmpty).toList();
  }

  void _onSearchChanged(String query) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 400), () {
      _search(query);
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      height: MediaQuery.of(context).size.height * 0.55,
      decoration: BoxDecoration(
        color: theme.scaffoldBackgroundColor,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20.r)),
      ),
      child: Column(
        children: [
          SizedBox(height: 8.h),
          Container(
            width: 40.w,
            height: 4.h,
            decoration: BoxDecoration(
              color: Colors.grey.shade300,
              borderRadius: BorderRadius.circular(2.r),
            ),
          ),
          Padding(
            padding: EdgeInsets.all(12.w),
            child: Container(
              height: 44.h,
              decoration: BoxDecoration(
                color: const Color(0xFFF5F5F5),
                borderRadius: BorderRadius.circular(12.r),
              ),
              child: Row(
                children: [
                  SizedBox(width: 12.w),
                  Icon(Icons.search, size: 20.sp, color: Colors.grey),
                  SizedBox(width: 8.w),
                  Expanded(
                    child: TextField(
                      controller: _searchController,
                      onChanged: _onSearchChanged,
                      decoration: InputDecoration(
                        hintText: 'Search GIFs...',
                        hintStyle: theme.textTheme.bodyMedium?.copyWith(
                          color: Colors.grey,
                        ),
                        border: InputBorder.none,
                        contentPadding: EdgeInsets.symmetric(vertical: 10.h),
                      ),
                      style: theme.textTheme.bodyMedium,
                    ),
                  ),
                ],
              ),
            ),
          ),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _gifs.isEmpty
                    ? Center(
                        child: Text(
                          'No GIFs found',
                          style: theme.textTheme.bodyMedium
                              ?.copyWith(color: Colors.grey),
                        ),
                      )
                    : GridView.builder(
                        padding: EdgeInsets.symmetric(horizontal: 8.w),
                        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: 2,
                          crossAxisSpacing: 8.w,
                          mainAxisSpacing: 8.w,
                        ),
                        itemCount: _gifs.length,
                        itemBuilder: (context, index) {
                          final gif = _gifs[index];
                          return GestureDetector(
                            onTap: () => Navigator.pop(context, gif.fullUrl),
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(8.r),
                              child: Image.network(
                                gif.previewUrl,
                                fit: BoxFit.cover,
                                loadingBuilder: (_, child, progress) {
                                  if (progress == null) return child;
                                  return Container(
                                    color: Colors.grey.shade200,
                                    child: const Center(
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                      ),
                                    ),
                                  );
                                },
                                errorBuilder: (_, __, ___) => Container(
                                  color: Colors.grey.shade200,
                                  child: const Center(
                                    child: Icon(Icons.broken_image_outlined),
                                  ),
                                ),
                              ),
                            ),
                          );
                        },
                      ),
          ),
          Padding(
            padding: EdgeInsets.only(bottom: 8.h),
            child: Text(
              'Powered by GIPHY',
              style: theme.textTheme.labelSmall?.copyWith(color: Colors.grey),
            ),
          ),
        ],
      ),
    );
  }
}

class _GifItem {
  const _GifItem({required this.previewUrl, required this.fullUrl});
  final String previewUrl;
  final String fullUrl;
}
