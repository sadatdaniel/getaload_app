import 'package:getaload/video_options.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final formats = <Map<String, dynamic>>[
    {'id': '140', 'vcodec': 'none', 'acodec': 'mp4a', 'size': 3000000},
    {'id': '137', 'vcodec': 'avc1', 'acodec': 'none', 'height': 1080, 'size': 50000000},
    {'id': '136', 'vcodec': 'avc1', 'acodec': 'none', 'height': 720, 'size': 20000000},
  ];

  test('size estimate: best video at or below the height plus the best audio', () {
    expect(estimateSize(formats, null), 53000000);
    expect(estimateSize(formats, 720), 23000000);
    expect(estimateSize(formats, 480), 0); // nothing that small: unknown, not just the audio
    expect(estimateSize(formats, null, audioOnly: true), 3000000);
  });

  test('remembered choices become the job request', () {
    expect(videoRequest({'audio': true, 'audioFormat': 'mp3'}), {'format': 'mp3'});
    expect(
      videoRequest({
        'quality': '720p',
        'container': 'mkv',
        'subs': ['en'],
      }),
      {
        'format': '720p',
        'container': 'mkv',
        'subs': ['en'],
      },
    );
    expect(videoRequest({}), {'format': 'best', 'container': 'mp4'});
  });
}
