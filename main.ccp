#include <iostream>
#include <fstream>
#include <vector>
#include <string>
#include <algorithm>
#include <climits>
#include <cctype>

using namespace std;

struct Bill {
    int nominal;
    int available;
    int chosen = 0;
};

// Функция для удаления всех пробелов, переносов строк и табов для надежного парсинга
string minifyJson(const string& str) {
    string minified = "";
    for (char c : str) {
        if (c != ' ' && c != '\n' && c != '\r' && c != '\t') {
            minified += c;
        }
    }
    return minified;
}

// Извлечение значения подстроки между заданными маркерами
string extractValue(const string& src, const string& key, char startDelim, char endDelim) {
    size_t pos = src.find(key);
    if (pos == string::npos) return "";
    pos = src.find(startDelim, pos + key.length());
    if (pos == string::npos) return "";
    size_t endPos = src.find(endDelim, pos + 1);
    if (endPos == string::npos) return "";
    return src.substr(pos + 1, endPos - pos - 1);
}

// Надежный парсинг входного файла
bool parseInput(const string& filename, vector<Bill>& wallet, int& amount, string& strategy) {
    ifstream file(filename);
    if (!file.is_open()) return false;

    string content((istreambuf_iterator<char>(file)), istreambuf_iterator<char>());
    file.close();

    // Очищаем весь JSON от пробелов и переносов
    string json = minifyJson(content);

    // Чтение amount
    size_t amtPos = json.find("\"amount\":");
    if (amtPos != string::npos) {
        amtPos += 9;
        string amtStr = "";
        while (amtPos < json.size() && isdigit(json[amtPos])) {
            amtStr += json[amtPos++];
        }
        if (!amtStr.empty()) amount = stoi(amtStr);
    }

    // Чтение strategy
    strategy = extractValue(json, "\"strategy\":", '"', '"');

    // Чтение wallet
    size_t walletPos = json.find("\"wallet\":");
    if (walletPos != string::npos) {
        walletPos = json.find("[", walletPos + 8);
        if (walletPos != string::npos) {
            int brackets = 1;
            string walletStr = "";
            size_t i = walletPos + 1;
            while (i < json.size() && brackets > 0) {
                if (json[i] == '[') brackets++;
                if (json[i] == ']') brackets--;
                if (brackets > 0) walletStr += json[i];
                i++;
            }

            // Парсим пары внутри walletStr, которая имеет вид [10,32],[20,2]...
            size_t p = 0;
            while ((p = walletStr.find("[", p)) != string::npos) {
                size_t comma = walletStr.find(",", p);
                size_t close = walletStr.find("]", p);
                if (comma != string::npos && close != string::npos && comma < close) {
                    int nom = stoi(walletStr.substr(p + 1, comma - p - 1));
                    int cnt = stoi(walletStr.substr(comma + 1, close - comma - 1));
                    wallet.push_back({nom, cnt, 0});
                }
                p = close + 1;
            }
        }
    }
    return true;
}

// Запись выходного JSON
void writeOutput(const string& filename, const vector<Bill>& dispense) {
    ofstream file(filename);
    file << "[\n  {\n    \"dispense\": [";
    bool first = true;
    for (const auto& b : dispense) {
        if (b.chosen > 0) {
            if (!first) file << ", ";
            file << "[" << b.nominal << ", " << b.chosen << "]";
            first = false;
        }
    }
    file << "]\n  }\n]\n";
    file.close();
}

// Поиск первого подходящего решения для MAX и MIN
bool solveMaxMin(int idx, int current_amount, vector<Bill>& wallet) {
    if (current_amount == 0) return true;
    if (idx >= (int)wallet.size() || current_amount < 0) return false;

    int max_possible = min(wallet[idx].available, current_amount / wallet[idx].nominal);
    for (int c = max_possible; c >= 0; --c) {
        wallet[idx].chosen = c;
        if (solveMaxMin(idx + 1, current_amount - c * wallet[idx].nominal, wallet)) {
            return true;
        }
    }
    wallet[idx].chosen = 0;
    return false;
}

// Поиск оптимального решения для UNIFORM
bool solveUniform(int idx, int current_amount, vector<Bill>& wallet, vector<int>& best_solution, int& min_diff) {
    if (current_amount == 0) {
        int max_c = 0, min_c = INT_MAX;
        for (const auto& b : wallet) {
            max_c = max(max_c, b.chosen);
            min_c = min(min_c, b.chosen);
        }
        int diff = max_c - min_c;
        if (diff < min_diff) {
            min_diff = diff;
            for (size_t i = 0; i < wallet.size(); ++i) {
                best_solution[i] = wallet[i].chosen;
            }
        }
        return true;
    }
    if (idx >= (int)wallet.size() || current_amount < 0) return false;

    bool found = false;
    int max_possible = min(wallet[idx].available, current_amount / wallet[idx].nominal);
    for (int c = max_possible; c >= 0; --c) {
        wallet[idx].chosen = c;
        if (solveUniform(idx + 1, current_amount - c * wallet[idx].nominal, wallet, best_solution, min_diff)) {
            found = true;
        }
    }
    wallet[idx].chosen = 0;
    return found;
}

int main() {
    vector<Bill> wallet;
    int amount = 0;
    string strategy = "";

    if (!parseInput("input.json", wallet, amount, strategy)) {
        cerr << "Ошибка чтения input.json" << endl;
        return 1;
    }

    bool success = false;

    if (strategy == "MAX") {
        sort(wallet.begin(), wallet.end(), [](const Bill& a, const Bill& b) {
            return a.nominal > b.nominal;
        });
        success = solveMaxMin(0, amount, wallet);

    } else if (strategy == "MIN") {
        sort(wallet.begin(), wallet.end(), [](const Bill& a, const Bill& b) {
            return a.nominal < b.nominal;
        });
        success = solveMaxMin(0, amount, wallet);

    } else if (strategy == "UNIFORM") {
        vector<int> best_solution(wallet.size(), 0);
        int min_diff = INT_MAX;
        success = solveUniform(0, amount, wallet, best_solution, min_diff);
        if (success) {
            for (size_t i = 0; i < wallet.size(); ++i) {
                wallet[i].chosen = best_solution[i];
            }
        }
    }

    vector<Bill> dispense;
    if (success) {
        dispense = wallet;
    }
    
    writeOutput("output.json", dispense);
    return 0;
}
