# Homebrew 배포

이 앱은 빌드 결과가 `.app` 번들이므로 Homebrew Formula가 아니라 Cask로 배포합니다. 공개 배포물은 로컬 개발용 `Apple Development` 서명이 아니라 `Developer ID Application` 서명과 Apple notarization을 모두 통과해야 합니다.

## 릴리스 준비

GitHub 저장소에 다음 Actions secrets를 등록합니다.

- `DEVELOPER_ID_APPLICATION_P12_BASE64`: Developer ID Application 인증서를 내보낸 `.p12`의 Base64 값
- `DEVELOPER_ID_APPLICATION_P12_PASSWORD`: `.p12` 내보내기 암호
- `APPLE_ID`: notarization에 사용할 Apple ID
- `APPLE_TEAM_ID`: Apple Developer Team ID
- `APPLE_APP_SPECIFIC_PASSWORD`: Apple ID의 앱 암호

워크플로는 임시 키체인 암호를 실행마다 생성합니다. 별도의 키체인 암호나 인증서 identity 문자열을 secret으로 둘 필요가 없습니다.

공개 버전은 `Support/Distribution.plist`에서 관리합니다. `v0.1.0`처럼 `v`와 해당 버전을 합친 태그만 릴리스할 수 있습니다.

```bash
git tag v0.1.0
git push origin v0.1.0
```

태그가 푸시되면 `.github/workflows/release.yml`이 다음 순서로 실행됩니다.

1. 태그와 배포 버전 일치 여부 확인
2. arm64 릴리스 빌드
3. Developer ID Application 서명
4. Apple notarization 제출 및 완료 대기
5. 앱에 notarization ticket staple 및 Gatekeeper 검증
6. 최종 ZIP, SHA-256 파일, Homebrew Cask 파일을 GitHub Release에 게시

## 개인 tap 게시

최초 릴리스가 성공한 뒤 공개 저장소 `RealTake/homebrew-tap`을 만들고, 릴리스에 첨부된 `external-display-viewer.rb`를 그 저장소의 `Casks/` 아래에 커밋합니다.

로컬에서도 최종 ZIP의 체크섬으로 같은 Cask를 재생성할 수 있습니다.

```bash
checksum="$(shasum -a 256 ExternalDisplayViewer-v0.1.0-macOS-arm64.zip | awk '{ print $1 }')"
Scripts/render-homebrew-cask.sh --sha256 "$checksum" > external-display-viewer.rb
```

사용자는 다음 명령으로 설치합니다.

```bash
brew tap RealTake/tap
brew install --cask external-display-viewer
```

tap에 반영하기 전에는 최소한 아래 검증을 통과시킵니다.

```bash
brew audit --new --cask RealTake/tap/external-display-viewer
brew install --cask RealTake/tap/external-display-viewer
brew uninstall --cask RealTake/tap/external-display-viewer
```

`Scripts/build-app.sh`는 개발 및 로컬 실행용 경로로 계속 유지합니다. 그 스크립트가 만든 Apple Development 서명 ZIP은 공개 Homebrew 배포물로 사용하지 않습니다.
