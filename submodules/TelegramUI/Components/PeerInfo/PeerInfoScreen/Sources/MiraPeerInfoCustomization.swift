import Foundation

func miraMaskPhoneNumber(_ formattedNumber: String) -> String {
    var result = ""
    var seenDigits = 0
    for character in formattedNumber {
        if character.isNumber {
            seenDigits += 1
            if seenDigits <= 1 {
                result.append(character)
            } else {
                result.append("\u{2022}")
            }
        } else {
            result.append(character)
        }
    }
    return result
}
