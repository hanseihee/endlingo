import "@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const LEVELS = ["A1", "A2", "B1", "B2", "C1", "C2"];
const ENVIRONMENTS = ["school", "work", "travel", "daily", "business"];

const LEVEL_GUIDE: Record<string, string> = {
  A1: `입문 레벨. 시나리오당 2문장. 기본 1000단어 이내. 현재시제, be동사, 단순 의문문만 사용. 아주 짧고 쉬운 문장.`,
  A2: `초급 레벨. 시나리오당 2~3문장. 일상 어휘. 과거시제, can/will, 간단한 접속사(and, but) 사용.`,
  B1: `중급 레벨. 시나리오당 3문장. 현재완료, if절, 관계대명사(who, which, that) 사용. 자연스러운 일상 영어.`,
  B2: `중고급 레벨. 시나리오당 3~4문장. 가정법, 분사구문, 복문 사용. 다양한 표현과 어휘.`,
  C1: `고급 레벨. 시나리오당 4문장. 도치, 강조구문, 관용표현 사용. 비즈니스/학술 뉘앙스 포함.`,
  C2: `최상급 레벨. 시나리오당 4~5문장. 원어민 수준 관용어, 문화적 맥락, 미묘한 뉘앙스 차이 설명 포함.`,
};

const ENV_TOPICS: Record<string, string[]> = {
  school: [
    "수업 중 질문하기, 교수님께 이메일 쓰기",
    "과제 마감 연장 요청, 팀 프로젝트 역할 분담",
    "스터디 그룹 모집, 시험 범위 확인",
    "도서관에서 자료 찾기, 참고문헌 질문",
    "수강 신청, 수업 변경 상담",
    "학교 동아리 가입, 행사 참여",
    "기숙사 생활, 룸메이트와 규칙 정하기",
    "졸업 요건 확인, 진로 상담",
    "실험실/연구실에서의 대화, 실습 보고서",
    "교환학생 지원, 유학 준비",
    "학교 식당에서 주문, 친구와 점심",
    "발표 준비, 피드백 받기",
    "시험 끝난 후 친구들과 계획 짜기",
    "교내 아르바이트, 조교 업무",
    "학교 행정실에서 서류 발급",
    "온라인 수업 접속 문제, 줌 에티켓",
    "학점 이의 신청, 성적표 확인",
    "논문 주제 선정, 지도교수 상담",
    "학교 체육관 이용, 운동 동아리",
    "캠퍼스 투어, 신입생에게 학교 소개",
    "학과 MT 계획, 장소와 활동 정하기",
    "복수전공/부전공 신청 상담",
    "학교 보건실 방문, 건강 상담",
    "학생회 선거, 공약 토론",
    "교내 카페에서 공부, 자리 맡기",
    "학교 셔틀버스 시간 확인, 통학 이야기",
    "장학금 신청, 추천서 부탁",
    "학교 축제 준비, 부스 운영",
    "해외 대학 지원, 자기소개서 작성",
    "수업 중 토론, 찬반 의견 나누기",
    "실험 결과 분석, 보고서 작성법",
    "프로그래밍 수업, 코드 에러 질문",
    "미술/음악 수업, 작품 감상 토론",
    "체육 수업, 팀 스포츠 규칙 설명",
    "학교 신문/방송국 활동, 인터뷰",
    "봉사활동 신청, 활동 계획 공유",
    "시험 기간 스트레스, 친구와 위로",
    "학교 근처 맛집 추천, 같이 가자고 제안",
    "교수님 연구실 방문, 논문 질문",
    "학위 논문 중간 발표, 수정 사항 논의",
    "외국인 친구와 언어 교환, 문화 차이",
    "학교 기념품 가게, 굿즈 구매",
    "여름/겨울 계절학기 수강 계획",
    "졸업식 준비, 학사모와 가운",
    "학교 동문 네트워크, 선배에게 조언 구하기",
    "캠퍼스 내 분실물 센터 방문",
    "학교 주차장 이용, 주차 허가증",
    "수업 녹화 요청, 결석 사유서 제출",
    "학교 상담 센터 이용, 고민 상담",
    "국제학생 오리엔테이션, 자기소개",
    "기말 프로젝트 발표, 팀원 역할 조율",
    "학교 도서관 스터디룸 예약",
    "학과 세미나 참석, 발표자에게 질문",
    "졸업 앨범 촬영, 포즈 정하기",
    "교내 창업 경진대회, 아이디어 발표",
    "학교 방학 중 인턴십 찾기",
    "수강 후기 작성, 수업 추천",
    "학교 근처 자취방 구하기, 부동산 문의",
    "교환학생 경험담 발표, 후배들에게 조언",
    "학교 건물 길 찾기, 강의실 위치 묻기",
    "수업 자료 공유, 노트 빌려달라고 부탁",
    "시험 부정행위 목격, 어떻게 할지 고민",
    "학교 동아리 공연/전시회 관람",
    "교수님 퇴임식, 감사 인사",
    "학교 근처 편의점에서 간식 사기",
    "졸업 후 진로 토론, 대학원 vs 취업",
    "학교 국제 행사, 각국 문화 소개",
    "비 오는 날 학교 생활, 우산 빌리기",
    "학교 컴퓨터실 이용, 프린터 고장",
    "수업 조별 과제 갈등 해결",
  ],
  work: [
    "업무 진행 상황 보고, 주간 미팅",
    "새 프로젝트 브레인스토밍, 아이디어 제안",
    "동료에게 도움 요청, 협업 조율",
    "상사에게 휴가 요청, 일정 조정",
    "신입사원 온보딩, 업무 인수인계",
    "업무 실수 보고, 해결 방안 논의",
    "점심 메뉴 정하기, 회식 계획",
    "재택근무 관련 소통, 화상회의 매너",
    "연봉 협상, 성과 면담",
    "퇴근 후 동료와 가벼운 대화",
    "사무용품 주문, 시설 문의",
    "고객 불만 처리, 서비스 개선 논의",
    "부서 이동, 새 팀 적응",
    "마감 기한 조정, 우선순위 정하기",
    "회의실 예약, 일정 충돌 해결",
    "출장 보고서 작성, 경비 정산",
    "팀 빌딩 활동, 워크숍 기획",
    "사내 메신저로 업무 요청, 톤 맞추기",
    "프리랜서/외주 업체와 소통",
    "사내 커피머신 고장, 시설팀에 연락",
    "새로운 소프트웨어 도입, 사용법 교육",
    "야근 상황 공유, 업무 분담 요청",
    "동료의 승진 축하, 선물 고르기",
    "월요일 아침 회의, 주간 목표 설정",
    "금요일 오후, 한 주 마무리 대화",
    "회사 복지 제도 문의, HR 상담",
    "사내 동호회 활동, 가입 안내",
    "업무 자동화 제안, 효율 개선",
    "고객 미팅 준비, 자료 검토",
    "회사 이벤트 기획, 역할 분담",
    "인턴 멘토링, 업무 지도",
    "이직 고민, 신뢰하는 동료와 상담",
    "회의 중 다른 의견 제시, 건설적 토론",
    "업무 매뉴얼 작성, 프로세스 정리",
    "해외 지사와 협업, 문화 차이 극복",
    "회사 연말 행사, 시상식 사회",
    "새 사무실로 이전, 자리 배치",
    "보안 교육, 비밀번호 관리",
    "직장 내 갈등 중재, 해결 방안 모색",
    "퇴사하는 동료 환송, 인사",
    "업무 미팅 후 액션 아이템 정리",
    "고객사 방문, 첫인상 관리",
    "사내 발표 대회, 주제 선정",
    "업무 스트레스 해소, 동료와 수다",
    "회사 근처 점심 맛집 개척",
    "택시/대중교통으로 외근, 경로 안내",
    "업무 일지 작성, 성과 기록",
    "사내 도서관/휴게실 이용",
    "연차 사용 계획, 팀 일정 조율",
    "회사 생일 파티, 케이크 주문",
    "프로젝트 마감 축하, 뒤풀이",
    "동료에게 업무 피드백 주기",
    "직장 건강검진, 일정 잡기",
    "사무실 온도 조절, 에어컨 분쟁",
    "회사 주차장 이용, 카풀 제안",
    "월급날, 동료와 재테크 이야기",
    "회사 구내식당 메뉴 이야기",
    "업무 중 전화 응대, 메시지 전달",
    "프린터/복합기 고장, IT팀 요청",
    "새 명함 주문, 디자인 논의",
    "출퇴근 길 이야기, 교통 정보 공유",
    "직장 내 친환경 캠페인 참여",
    "업무 관련 자격증 공부, 동료와 스터디",
    "해외 출장 준비, 비자/항공편",
    "사내 설문조사 참여, 개선 의견 제출",
    "업무용 노트북/장비 교체 요청",
    "동료의 결혼/출산 축하",
    "팀 점심 배달 주문, 취향 맞추기",
    "사무실 식물 관리, 인테리어 이야기",
    "업무 관련 외부 세미나 참석 후기",
  ],
  travel: [
    "공항 체크인, 보안 검색대 통과",
    "호텔 체크인/아웃, 객실 문제 해결",
    "현지 맛집에서 주문, 음식 추천 받기",
    "길을 잃었을 때 도움 요청, 지도 보기",
    "관광지 입장권 구매, 가이드 투어",
    "렌터카 빌리기, 주유소에서 대화",
    "기차/버스표 구매, 환승 방법 묻기",
    "쇼핑몰에서 할인 문의, 환불/교환",
    "현지인과 문화 이야기, 추천 장소 묻기",
    "숙소 예약 변경, 취소 요청",
    "여행 중 아플 때 약국/병원 방문",
    "공항 면세점 쇼핑, 면세 한도 확인",
    "해외에서 은행/환전소 이용",
    "에어비앤비 호스트와 소통, 체크인 방법",
    "여행 사진 찍어달라고 부탁, 현지 축제 참여",
    "짐 분실 신고, 항공사 클레임",
    "크루즈/페리 탑승, 선상 활동",
    "트레킹/하이킹 가이드와 대화",
    "해변에서 장비 대여, 액티비티 예약",
    "귀국 전 기념품 쇼핑, 포장 요청",
    "비행기 안에서 승무원과 대화, 기내식 선택",
    "공항 라운지 이용, 와이파이 연결",
    "택시/우버 호출, 목적지 설명",
    "호스텔 체크인, 다른 여행자와 인사",
    "여행 보험 관련 문의, 사고 접수",
    "현지 시장/야시장 구경, 흥정하기",
    "박물관/미술관 관람, 오디오 가이드 대여",
    "스쿠버다이빙/스노클링 안전 교육",
    "캠핑장 예약, 장비 대여",
    "와이너리/양조장 투어, 시음",
    "요리 클래스 참여, 현지 음식 배우기",
    "자전거 대여, 도시 탐험",
    "야간 투어, 도시 야경 감상",
    "서핑 레슨, 강사와 대화",
    "스키/스노보드 리조트, 장비 렌탈",
    "온천/스파 이용, 예약 문의",
    "여행 중 빨래, 코인 세탁소 이용",
    "현지 교통카드 충전, 지하철 노선 확인",
    "여행 동행 구하기, 일정 맞추기",
    "동물원/수족관 방문, 아이와 함께",
    "테마파크 입장, 놀이기구 탑승",
    "사막 투어, 낙타 타기",
    "정글/열대우림 탐험, 가이드 설명",
    "빙하 트레킹, 안전 장비 확인",
    "핫에어벌룬 탑승, 예약 확인",
    "로컬 펍에서 맥주 주문, 현지인과 대화",
    "스트리트 푸드 먹어보기, 재료 질문",
    "여행지에서 우편 엽서 보내기",
    "공항 환승, 대기 시간 활용",
    "여행 마지막 날, 체크리스트 확인",
    "여행 후기 작성, 숙소 리뷰",
    "현지 축구/야구 경기 관람, 티켓 구매",
    "플리마켓 구경, 수공예품 구매",
    "카약/래프팅 예약, 안전 수칙",
    "와이파이/유심 구매, 데이터 확인",
    "여행 중 날씨 확인, 일정 변경",
    "사진 명소 찾기, 인스타 핫플",
    "현지 대중목욕탕/사우나 체험",
    "푸드 투어 참가, 음식 역사 듣기",
    "기차 여행, 차창 밖 풍경 대화",
    "배낭여행 짐 싸기, 필수품 체크",
    "여행지 일출/일몰 감상 스팟",
    "보트 투어, 섬 호핑",
    "현지 언어 기본 인사, 감사 표현",
    "여행 중 충전기/어댑터 구하기",
    "공항 세관 신고, 반입 금지 물품",
    "여행 친구와 비용 정산, 더치페이",
    "현지 요가/명상 클래스 참여",
    "골프장 예약, 라운딩 대화",
    "낚시 투어, 장비 사용법",
    "헬리콥터/경비행기 투어 예약",
    "여행지 미니 마트에서 간식 쇼핑",
    "현지 페스티벌/카니발 참여",
    "밤하늘 별 관측 투어",
    "여행 중 분실물 찾기, 경찰서 방문",
    "승마 체험, 안전 수칙",
  ],
  daily: [
    "카페에서 음료 주문, 커스텀 요청",
    "택배 수령, 배송 문제 문의",
    "이웃과 인사, 소음 문제 이야기",
    "전화로 예약하기, 일정 변경",
    "병원 접수, 증상 설명",
    "은행에서 계좌 개설, 송금 문의",
    "마트에서 장보기, 계산대 대화",
    "미용실 예약, 스타일 설명",
    "운동/헬스장 등록, 트레이너와 대화",
    "반려동물 병원 방문, 증상 설명",
    "집 수리 요청, 관리사무소 연락",
    "중고 물품 거래, 가격 흥정",
    "세탁소 이용, 옷 수선 요청",
    "우체국에서 소포 보내기",
    "자동차 정비소, 고장 설명",
    "약국에서 약 구매, 복용법 확인",
    "음식 배달 주문, 리뷰 남기기",
    "도서관 이용, 도서 대출/반납",
    "친구와 영화/공연 계획",
    "새 집으로 이사, 인터넷 설치",
    "주말 브런치, 친구와 레스토랑 방문",
    "헬스장에서 요가/필라테스 수업 등록",
    "동네 빵집에서 빵 고르기, 추천 받기",
    "주민센터 방문, 서류 발급",
    "자전거 타이어 수리, 자전거 가게",
    "네일샵 예약, 디자인 고르기",
    "집에서 요리, 레시피 공유",
    "주말 등산, 산행 코스 추천",
    "아이 학교 상담, 선생님과 대화",
    "동네 산책, 강아지 산책 중 이웃 만남",
    "가구 조립, 설명서 읽기",
    "온라인 쇼핑 반품, 고객센터 연락",
    "집 인테리어, 페인트칠 계획",
    "동네 축제/행사 참여",
    "새 핸드폰 구매, 요금제 상담",
    "자동차 세차, 세차장 이용",
    "정수기/공기청정기 설치, AS 요청",
    "이사 인사, 새 이웃에게 선물",
    "집 와이파이 고장, 인터넷 회사 연락",
    "건강검진 예약, 결과 확인",
    "치과 예약, 치료 상담",
    "안경점 방문, 시력검사와 안경 맞추기",
    "세무서 방문, 세금 관련 문의",
    "부동산 방문, 집 구하기",
    "보험 가입 상담, 조건 비교",
    "주말 영화관, 팝콘과 음료 주문",
    "친구 생일 파티 준비, 선물 포장",
    "꽃집에서 꽃다발 주문",
    "사진관에서 증명사진 촬영",
    "운전면허 시험 접수, 준비 이야기",
    "동네 수영장 등록, 수영복 구매",
    "주말 캠핑 준비, 장비 체크",
    "반찬 가게에서 반찬 주문",
    "새벽 배송 이용, 주문 확인",
    "동네 세탁 카페 이용, 대기 시간",
    "집 근처 공원에서 피크닉",
    "전기/가스 요금 문의, 자동이체 설정",
    "주말 볼링/당구장, 친구와 게임",
    "집 청소 도우미 예약, 요청사항 전달",
    "중고차 구매, 시승과 상담",
    "동네 문화센터 수강 신청",
    "재활용 분리수거 방법 묻기",
    "집 발코니 화분 관리, 식물 가게 방문",
    "지역 도서관 독서 모임 참여",
    "아침 조깅, 러닝 메이트와 대화",
    "동네 빨래방 이용, 세탁기 사용법",
    "집 보안 시스템 설치, 상담",
    "아이 생일파티 계획, 장소 예약",
    "친구 집 방문, 집들이 선물",
    "동네 떡집에서 명절 떡 주문",
    "가전제품 AS 접수, 수리 기사 방문",
    "동네 놀이터에서 아이들과 놀기",
    "약속 시간에 늦을 때 연락하기",
    "친구와 통화, 근황 나누기",
    "반려동물 미용실 예약",
    "주말 드라이브 계획, 코스 정하기",
  ],
  business: [
    "프레젠테이션 발표, 질의응답 대응",
    "해외 거래처와 화상회의, 시차 조율",
    "계약 조건 협상, 수정 요청",
    "분기 실적 보고, 매출 분석",
    "신규 사업 제안, 투자 유치 피칭",
    "비즈니스 네트워킹, 명함 교환",
    "출장 일정 잡기, 경비 정산",
    "컨퍼런스 참석, 발표자 소개",
    "해외 파트너와 만찬, 비즈니스 매너",
    "프로젝트 킥오프 미팅, 목표 설정",
    "위기 관리, 고객사 클레임 대응",
    "인사 평가, 팀원 피드백 전달",
    "사내 교육/워크숍 진행",
    "공급업체 선정, 견적 비교",
    "합작 투자 논의, MOU 체결",
    "연간 사업 계획 수립, 예산 배정",
    "시장 조사 결과 발표, 경쟁사 분석",
    "브랜드 리뉴얼 논의, 마케팅 전략",
    "해외 전시회 참가, 부스 운영",
    "법률 검토, 계약서 수정 논의",
    "M&A 실사, 기업 가치 평가",
    "이사회 보고, 주요 안건 논의",
    "채용 면접 진행, 후보자 평가",
    "고객사 방문, 제품 데모",
    "비즈니스 이메일 작성, 격식 있는 표현",
    "해외 법인 설립, 현지 규정 확인",
    "지식재산권 보호, 특허 출원 논의",
    "사업 파트너십 제안, 윈윈 전략",
    "공장/생산시설 견학, 품질 관리",
    "유통 채널 확대, 판매 전략",
    "디지털 전환 전략, IT 투자 논의",
    "ESG 경영, 지속가능성 보고서",
    "해외 바이어 상담, 샘플 발송",
    "프랜차이즈 계약, 로열티 협상",
    "위기 커뮤니케이션, 보도자료 작성",
    "신제품 런칭 이벤트, 미디어 초청",
    "글로벌 팀 화상회의, 문화 차이 극복",
    "스타트업 투자 심사, 피칭 데이",
    "기업 사회공헌 활동 기획",
    "업계 세미나 발표, 패널 토론",
    "리스크 관리, 비상 대응 계획",
    "기업 구조조정, 인력 재배치",
    "해외 규제 대응, 컴플라이언스",
    "연말 결산, 감사 준비",
    "전략적 제휴, 공동 마케팅",
    "고객 만족도 조사, 서비스 개선",
    "물류/공급망 최적화 논의",
    "임원 코칭, 리더십 개발",
    "사내 혁신 공모전, 아이디어 심사",
    "해외 시장 진출, 현지화 전략",
    "기업 문화 개선, 직원 만족도 조사",
    "세무/회계 감사 대응",
    "비즈니스 영어 프레젠테이션 스킬",
    "해외 출장 후 결과 보고, 후속 조치",
    "기업 홍보 영상 기획, 시나리오 논의",
    "해외 클라이언트 접대, 문화적 배려",
    "사업 실패 분석, 피봇 전략",
    "기업 인수 후 통합, PMI 과정",
    "데이터 기반 의사결정, KPI 설정",
    "해외 컨설팅 업체 미팅, 보고서 리뷰",
    "비즈니스 런치, 격식 있는 식사 매너",
    "분쟁 조정, 중재 절차 논의",
    "조직 개편, 새 부서 신설",
    "글로벌 인재 채용, 다양성 정책",
    "벤처캐피탈 IR 미팅, 투자 조건",
    "사업 확장, 지점/지사 개설",
    "고객 로열티 프로그램 기획",
    "업무 효율화, 프로세스 자동화 논의",
    "해외 파트너 공장 품질 감사",
    "비즈니스 네트워킹 파티, 스몰토크",
  ],
};

function pickDailyTopic(environment: string, date: string): string {
  const topics = ENV_TOPICS[environment];
  // 날짜 + 환경 조합으로 매일 다른 토픽 선택
  const dateNum = parseInt(date.replace(/-/g, ""), 10);
  const index = (dateNum + environment.length) % topics.length;
  return topics[index];
}

function buildPrompt(level: string, environment: string, date: string): string {
  const todayTopic = pickDailyTopic(environment, date);
  return `당신은 한국인을 위한 영어 교육 전문가입니다.
아래 조건에 맞는 영어 학습 콘텐츠를 JSON으로 생성하세요.

조건:
- 레벨: ${level} (${LEVEL_GUIDE[level]})
- 오늘의 주제: ${todayTopic}
- 날짜: ${date}
- 시나리오 수: 정확히 3개

요구사항:
1. 테마는 해당 환경에서 실제로 마주치는 상황이어야 합니다
2. 3개의 시나리오는 서로 다른 상황이되 하나의 테마로 자연스럽게 연결되어야 합니다
3. 영어 문장은 ${level} 수준의 문법을 자연스럽게 포함해야 합니다
4. 문법 포인트는 시나리오당 2~3개:
   - pattern: 영어 문법 패턴이나 구동사를 영어로 표기 (예: "Work on + noun", "Look forward to + -ing", "Have been + -ing")
   - explanation: 한국어로 쉽고 친절하게 해당 패턴의 의미와 사용법 설명
   - example: 해당 패턴을 사용한 짧은 영어 예문 1개 (시나리오 문장과 다른 예문)
5. 구동사(phrasal verb)가 문장에 사용되었다면 반드시 문법 포인트에 포함하세요
6. sentence_ko 번역 규칙:
   - 직역이 아닌 의역으로 자연스러운 한국어 문장을 작성하세요
   - 한국어 어순과 조사를 자연스럽게 사용하세요
   - 영어 구조를 그대로 옮기지 마세요 (예: "나는 ~하는 것을 원한다" → "~하고 싶어요")
   - 존댓말(해요체)로 통일하세요
   - 관용적 한국어 표현을 적극 사용하세요
   - 번역투 표현을 피하세요 (예: "그것은" → 생략, "~하는 것" → 자연스러운 표현으로)
7. context는 한국어로 이 상황이 어떤 상황인지 한 줄로 설명

반드시 아래 JSON 형식만 출력하세요. 다른 텍스트 없이 JSON만 출력:
{
  "theme_ko": "오늘의 ○○ 영어",
  "theme_en": "Daily ○○ English",
  "scenarios": [
    {
      "order": 1,
      "title_ko": "시나리오 제목 (한국어)",
      "title_en": "Scenario Title (English)",
      "context": "이 상황에 대한 한국어 설명",
      "sentence_en": "English sentences here.",
      "sentence_ko": "한국어 번역",
      "grammar": [
        { "pattern": "Work on + noun", "explanation": "~에 대해 작업하다. 특정 과제나 프로젝트에 집중할 때 사용합니다.", "example": "She is working on her homework." }
      ]
    },
    {
      "order": 2,
      "title_ko": "...",
      "title_en": "...",
      "context": "...",
      "sentence_en": "...",
      "sentence_ko": "...",
      "grammar": [{ "pattern": "...", "explanation": "...", "example": "..." }]
    },
    {
      "order": 3,
      "title_ko": "...",
      "title_en": "...",
      "context": "...",
      "sentence_en": "...",
      "sentence_ko": "...",
      "grammar": [{ "pattern": "...", "explanation": "...", "example": "..." }]
    }
  ]
}`;
}

async function generateLesson(
  apiKey: string,
  level: string,
  environment: string,
  date: string,
): Promise<Record<string, unknown> | null> {
  const prompt = buildPrompt(level, environment, date);

  const response = await fetch("https://api.openai.com/v1/chat/completions", {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
      "Authorization": `Bearer ${apiKey}`,
    },
    body: JSON.stringify({
      model: "gpt-4o-mini",
      max_tokens: 2048,
      temperature: 0.9,
      response_format: { type: "json_object" },
      messages: [
        { role: "system", content: "You are a JSON-only response bot. Always respond with valid JSON." },
        { role: "user", content: prompt },
      ],
    }),
  });

  if (!response.ok) {
    const err = await response.text();
    console.error(`OpenAI API error for ${level}/${environment}: ${err}`);
    return null;
  }

  const result = await response.json();
  const text = result.choices?.[0]?.message?.content;
  if (!text) {
    console.error(`No content in response for ${level}/${environment}`);
    return null;
  }

  try {
    return JSON.parse(text);
  } catch {
    console.error(`Failed to parse JSON for ${level}/${environment}: ${text.slice(0, 200)}`);
    return null;
  }
}

Deno.serve(async (req) => {
  try {
    const openaiKey = Deno.env.get("OPENAI_API_KEY");
    if (!openaiKey) {
      return new Response(JSON.stringify({ error: "OPENAI_API_KEY not set" }), {
        status: 500,
        headers: { "Content-Type": "application/json" },
      });
    }

    const supabaseUrl = Deno.env.get("SUPABASE_URL")!;
    const supabaseServiceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
    const supabase = createClient(supabaseUrl, supabaseServiceKey);

    // KST 기준 오늘 날짜
    const today = new Date().toLocaleDateString("en-CA", { timeZone: "Asia/Seoul" });

    // 요청 body에서 특정 레벨/날짜 지정 가능
    let targetLevel: string | null = null;
    let targetDate: string | null = null;
    try {
      const body = await req.json();
      targetLevel = body.level || null;
      targetDate = body.date || null;
    } catch {
      // body 없으면 기본값
    }

    const dateToUse = targetDate || today;
    const levelsToGenerate = targetLevel ? [targetLevel] : LEVELS;

    // 이미 생성된 레슨 확인
    const { data: existing } = await supabase
      .from("daily_lessons")
      .select("level, environment")
      .eq("date", dateToUse);

    const existingSet = new Set(
      (existing || []).map((e: { level: string; environment: string }) => `${e.level}_${e.environment}`),
    );

    let generated = 0;
    let skipped = 0;
    let failed = 0;

    for (const level of levelsToGenerate) {
      // 같은 레벨의 5개 환경을 동시 생성 (병렬)
      const promises = ENVIRONMENTS.map(async (env) => {
        const key = `${level}_${env}`;
        if (existingSet.has(key)) {
          skipped++;
          return;
        }

        const lesson = await generateLesson(openaiKey, level, env, dateToUse);
        if (!lesson) {
          failed++;
          return;
        }

        const { error } = await supabase.from("daily_lessons").insert({
          date: dateToUse,
          level: level,
          environment: env,
          theme_ko: lesson.theme_ko,
          theme_en: lesson.theme_en,
          scenarios: lesson.scenarios,
        });

        if (error) {
          console.error(`Insert error for ${key}: ${error.message}`);
          failed++;
        } else {
          generated++;
          console.log(`Generated: ${key}`);
        }
      });

      await Promise.all(promises);
    }

    return new Response(
      JSON.stringify({
        date: dateToUse,
        generated,
        skipped,
        failed,
        total: levelsToGenerate.length * ENVIRONMENTS.length,
      }),
      { headers: { "Content-Type": "application/json" } },
    );
  } catch (err) {
    console.error("Unexpected error:", err);
    return new Response(JSON.stringify({ error: String(err) }), {
      status: 500,
      headers: { "Content-Type": "application/json" },
    });
  }
});
