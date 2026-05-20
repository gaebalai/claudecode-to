[한국어](README.md) | [English](README.en.md)

# mbti-16types

MBTI® 의 16타입 인격의 에이전트를 소환하여, 어떤 주제든 논의·리뷰·조언하게 하는 Claude Code 플러그인.

**아이디어 도출·설계 판단·라이프/커리어 선택·코드 리뷰·윤리적 토픽 등, 의견이 갈릴 만한 모든 주제** 에 쓸 수 있습니다. 시점의 다양성이 더 나은 결론으로 이어진다, 는 전제로 디자인되었습니다.

## 왜 만들었나

Claude에게 리뷰를 부탁하면, 무난하고 평균적인 답이 돌아오기 쉽습니다. 정말 원하는 것은, 입장이 다른 여러 인격이 **의도적으로 치우친 의견**을 부딪쳐 본 결과로부터, 자신이 놓치고 있던 시점을 줍는 것입니다. mbti-16types는 그를 위해, 16타입 각각의 **가치관·사고 경향·말투**를 독립된 프롬프트로 정의하고, 병렬로 주제를 부딪칩니다.

## 설치

```
/plugin marketplace add gaebalai/claudecode-to
/plugin install mbti-16types
```

로컬 개발이라면:

```
/plugin marketplace add <이 리포지터리를 클론한 경로>
/plugin install mbti-16types
```

## 커맨드

| 커맨드 | 동작 |
|---|---|
| `/mind <type> [--mode=...] <topic>` | 단일 타입의 의견 |
| `/pair <a> <b> [--mode=...] <topic>` | 2타입의 디베이트(입론 → 반론 → 재반론/착지) |
| `/minds [--mode=...] [--types=a,b,...] [--n=N] [--save] [--out=<path>] <topic>` | 전체 16타입 병렬+합의(heavy에서는 반론 라운드 포함). `--save`로 결과를 파일에 저장. |

## 모드

| 모드 | 내용 | 용도 |
|---|---|---|
| `light` | score + 한 줄 코멘트만 | 빠르게 다양성을 보고 싶다·토큰 절약 |
| `middle`(기본) | 경량 패스 → 발산 의견의 심층 분석 → 합의 | 첫인상을 충족하는 밸런스 중시 |
| `heavy` | + 반론 라운드 + 합의의 재구성 | 무거운 의사결정이나 기사 소재에 |

`/minds`의 **합의**는 다음 4개 섹션 고정(발산을 피하기 위한 정형 루브릭):

1. **score 분포** — 최저·최빈·최고를 한 문장으로
2. **주요한 대립축**(2~3개) — 각 축의 대표 타입군을 병기
3. **놓치기 쉬운 시점**(1~3개) — 출처 타입을 명기
4. **절충점 후보**(2~3안) — 각 안에 '찬동할 것 같은 타입/적합성/리스크'를 붙임

## 사용 예

### 아이디어 도출(이 플러그인을 만든 주된 동기)

```
/minds velog 글 제목 후보, 와닿는 것은 어느 것?
/minds --mode=heavy 신규 서비스의 네이밍 안을 좁히고 싶다
/mind enfp 이번 주말 리프레시 안을 3개 내줘
/pair entp infj 부업으로 무엇을 시작할까
```

실제 예: [`Outputs/velog-title-discussion.md`](Outputs/velog-title-discussion.md) — 이 README가 있는 리포지터리 자체를 소재로, velog 글 제목을 `/minds`로 논의하게 한 완전 로그(Phase 1 표 → Phase 2 심층 분석 → Phase 3 합의의 3안에 착지).

### 설계 판단 / 코드 리뷰

```
/mind intj 이 API 설계, 장기적으로 파탄나지 않을까?
/pair istj entp --mode=heavy 모놀리스에서 분할할까 유지할까
/minds --mode=heavy --types=intj,entj,istp 다음에 채택할 DB
/minds AI에 의한 코드 리뷰의 시비
```

### 라이프·커리어 선택

```
/minds 이직할까 지금 회사에서 승진을 기다릴까
/pair infj entj --mode=heavy 부업을 본업화할까
/mind enfp --mode=heavy 재택근무와 출근의 균형
```

### 샘플 출력(`/mind intj`의 light 모드)

```
score: 2
stance: 단기의 편안함을 위해 장기의 최적화를 희생하고 있다
key_axis: 장기 최적화
concern: 이 선택을 3년 계속했을 때, 철수 비용이 지수적으로 불어난다
```

### 샘플 출력(`/minds --mode=light`의 1차 평가표 이미지)

```
| type | score | stance | key_axis | concern |
|---|---|---|---|---|
| intj | 2 | 장기로 보면 비효율 | 장기 최적화 | 철수 비용의 증대 |
| enfp | 5 | 지금의 자신이 기쁜 선택이면 된다 | 자유 | 번아웃에 대한 주의 |
| istj | 3 | 전례가 있다면 가능, 없다면 신중하게 | 실증 | 검증 데이터가 빈약 |
...
```

## 결과의 저장

`/minds --save`로 실행 결과(Phase 1 표·심층 분석·합의 모두)를 `Outputs/<timestamp>-minds-<mode>.md`에 저장합니다. `--out=<path>`로 저장 위치를 명시 지정도 가능. 글 소재나 의사결정 로그로 남기고 싶을 때에.

## 사용 가능한 타입

`intj`, `intp`, `entj`, `entp`, `infj`, `infp`, `enfj`, `enfp`, `istj`, `isfj`, `estj`, `esfj`, `istp`, `isfp`, `estp`, `esfp`

각 타입의 인격은 `agents/<type>.md`에 정의되어 있습니다. 주기능·부기능을 포함한 인지 특성, 가치관의 핵심, 강점·약점, 논의에서의 버릇, 전형적인 표현까지 명시되어 있으므로, 출력에 시각적인 개성이 드러납니다.

## 설계 메모

- **인격은 프롬프트에 직접 작성**. 중앙집권적인 '가치관 벡터 표' 같은 데이터 구조는 갖지 않습니다(이중 관리를 피하기 위해).
- **subagent로의 호출은 반드시 병렬**. `/minds`는 최대 16병렬까지 펼쳐지므로, 순차로 하면 레이턴시가 크게 악화됩니다.
- **subagent의 출력 포맷은 호출한 커맨드가 지정**. agent 측에는 포맷 사양을 갖게 하지 않고, 16타입 × 3모드의 조합 폭발을 피하고 있습니다.
- **subagent의 출력은 가공하지 않고 그대로 표시**. 요약이나 바꿔 말하기는 금지(인격의 말투가 사라져 버리므로).

## 라이선스

[MIT](LICENSE) © Jaewoo Kim

## 상표에 대하여

이 플러그인은 Myers-Briggs Type Indicator® (MBTI®) 의 권리자인 The Myers & Briggs Foundation, 및 16Personalities® 를 제공하는 NERIS Analytics와는 무관하며, 그들로부터 인가·추천을 받은 것이 아닙니다. '16타입'은 심리학 일반에서 쓰이는 유형 표현으로서 참조하고 있습니다.
