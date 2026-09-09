from pydub import AudioSegment
a = AudioSegment.from_wav('source_clips/speaker187_187_003_0011.wav')
b = AudioSegment.from_wav('source_clips/speaker191_191_003_0006.wav')
(a + b).export('generated_cases/00_baseline_quiet.wav', format='wav')
print("완료!")