import Foundation

struct DARTDisclosure {
    let rceptNo: String      // 접수번호 (고유 ID)
    let corpName: String     // 기업명
    let stockCode: String    // 종목코드
    let reportName: String   // 공시명
    let receivedDate: String // 접수일자 YYYYMMDD
    let disclosureType: String // pblntf_ty: A=정기, B=주요사항, C=발행, D=지분, I=거래소 등
}
