import 'dart:io';

import 'package:flutter/material.dart';

import '../../../core/network/network_client.dart';

/// Artwork used by detail views; image requests inherit the global User-Agent.
class MediaArtwork extends StatelessWidget {
  const MediaArtwork({
    super.key,
    required this.imageUrl,
    required this.network,
    this.width = 156,
    this.height = 224,
    this.cachedFile,
  });

  final String? imageUrl;
  final NetworkClient network;
  final double width;
  final double height;
  final File? cachedFile;

  @override
  Widget build(BuildContext context) {
    final uri = Uri.tryParse(imageUrl ?? '');
    final valid =
        uri != null && (uri.scheme == 'http' || uri.scheme == 'https');
    final scheme = Theme.of(context).colorScheme;
    final decodedWidth = (width * MediaQuery.devicePixelRatioOf(context))
        .ceil();
    return ClipRRect(
      borderRadius: BorderRadius.circular(10),
      child: SizedBox(
        width: width,
        height: height,
        child: ColoredBox(
          color: scheme.surfaceContainerHighest,
          child: cachedFile != null
              ? Image.file(
                  cachedFile!,
                  fit: BoxFit.cover,
                  cacheWidth: decodedWidth > 0 ? decodedWidth : 1,
                  errorBuilder: (context, error, stackTrace) =>
                      const Center(child: Icon(Icons.movie_outlined, size: 36)),
                )
              : valid
              ? Image.network(
                  uri.toString(),
                  headers: network.imageHeaders,
                  fit: BoxFit.cover,
                  cacheWidth: decodedWidth > 0 ? decodedWidth : 1,
                  errorBuilder: (context, error, stackTrace) =>
                      const Center(child: Icon(Icons.movie_outlined, size: 36)),
                )
              : const Center(child: Icon(Icons.movie_outlined, size: 36)),
        ),
      ),
    );
  }
}
