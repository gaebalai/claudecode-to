---
description: "Get one personality type's opinion on a topic. Usage: /mind <type> [--mode=light|middle|heavy] <topic>"
---

사용자가 `/mind`를 실행했습니다.

인자: $ARGUMENTS

## 인자 해석

1. `--mode=light` / `--mode=middle` / `--mode=heavy`(또는 공백 구분의 `--mode light` 형식)가 있으면 꺼내어 모드로 한다. 지정이 없으면 `middle`.
2. 남은 인자의 첫 단어를 타입명으로 꺼내어, 소문자로 정규화한다(예: `INTJ` → `intj`).
3. 나머지 문자열을 "주제"로 다룬다.

## 사용 가능한 타입

`intj`, `intp`, `entj`, `entp`, `infj`, `infp`, `enfj`, `enfp`, `istj`, `isfj`, `estj`, `esfj`, `istp`, `isfp`, `estp`, `esfp`

## 에러 처리

- 인자가 비어 있거나, 타입명만 있고 주제가 없는 경우:
  ```
  Usage: /mind <type> [--mode=light|middle|heavy] <topic>
  Example: /mind intj 이 API 설계 어떻게 생각해?
  Example: /mind enfp --mode=heavy 재택근무와 출근의 균형
  ```
- 타입명이 위 리스트에 없는 경우: `사용 가능한 타입: intj, intp, entj, entp, infj, infp, enfj, enfp, istj, isfj, estj, esfj, istp, isfp, estp, esfp`라고 반환하고 종료.
- 모드명이 `light` / `middle` / `heavy` 중 어느 것도 아닌 경우: 그 사실을 전하고 종료.

## 실행

지정 타입의 subagent를 Task 툴로 한 번만 호출한다. 프롬프트에는 다음을 포함할 것:

- 주제(사용자가 건넨 문자열을 그대로)
- '당신은 지정된 인격으로서 이 주제에 대한 의견을 진술해 주세요'라는 지시
- 아래의 모드별 '출력 포맷 지정'을 그대로 붙여넣기

### light 모드 출력 포맷 지정

```
주제에 대해, 다음 4행만으로 답해 주세요. 인사·서론·요약은 일절 불필요합니다.

score: <1~5의 정수. 당신의 가치관에서 본 종합 평가. 5=완전 찬성, 3=조건부, 1=완전 반대>
stance: <한 줄의 입장 선언>
key_axis: <판단에 가장 크게 작용한 당신의 가치관의 축(당신의 인격 정의에 나오는 말로)>
concern: <당신의 가치관에서 본 가장 큰 우려를 한 줄로>
```

### middle 모드 출력 포맷 지정

```
주제에 대해, 다음 구성으로 약 150~250자로 답해 주세요. 당신의 말투를 반드시 유지해 주세요. 인사·서론·요약은 불필요합니다.

stance: <한 줄의 입장 선언>
reasoning: <당신의 가치관에서 그 입장에 이르는 논리의 흐름을 2~3문장으로. 당신의 말투로>
watchpoint: <당신의 가치관에서 본 놓치기 쉬운 점·추천 포인트·걸리는 점을 1~2문장으로>
```

### heavy 모드 출력 포맷 지정

```
주제에 대해, 다음 구성으로 약 300~500자로 답해 주세요. 당신의 말투를 반드시 유지해 주세요. 인사·서론·요약은 불필요합니다.

stance: <한 줄의 입장 선언>
reasoning: <당신의 가치관에서 그 입장에 이르는 논리의 흐름을, 구체적 예시나 반례를 섞어 3~5문장으로>
strongest_case: <당신의 입장이 가장 강해지는 케이스·전제 조건을 1~2문장으로>
weakest_case: <당신의 입장이 무너지는 케이스·전제 조건을 1~2문장으로(스스로도 인정하는 약점)>
```

## 출력

subagent가 반환한 내용을 그대로, 가공하지 않고 표시한다. 맨 앞에 `### <TYPE>(<mode>)` 같은 제목을 한 줄만 붙여도 된다.
