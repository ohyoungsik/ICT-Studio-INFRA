import http from 'k6/http';
import { sleep } from 'k6';
export const options = {
// 부하를 생성하는 단계(stages)를 설정
stages: [
// 10분에 걸쳐 vus(virtual users, 가상 유저수)가 6000에 도달하도록 설정
{ duration: '10m', target: 6000 }
],
};
export default function () {
    // API 주소로 GET 요청
    // http.get('http://{EC2 IP 주소}/health');
    http.get('http://prod-ict-alb-814737022.ap-northeast-2.elb.amazonaws.com/health');
    // 1초 휴식
    sleep(1);
}